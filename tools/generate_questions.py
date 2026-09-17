#!/usr/bin/env python3
"""
漢字コンバット question generator.

Builds ~1000 読み (reading) multiple-choice questions per 漢検 level (10級〜1級)
from:
  * data/official/*.txt  : official 級別漢字表 (2020改正, 10級〜準2級)
  * KANJIDIC2 (jamdict)  : kanji readings / grade / freq / JIS level
  * JMdict    (jamdict)  : word -> reading pairs

Outputs Luau modules to src/server/data/ and stats to tools/stats.json.
Deterministic (fixed RNG seed).
"""
import json
import os
import random
import re
import sqlite3
import sys
import unicodedata
from collections import defaultdict
from itertools import product

def _find_jamdict_db():
    env = os.environ.get('JAMDICT_DB')
    if env and os.path.isfile(env):
        return env
    candidates = [
        '/usr/local/lib/python3.11/dist-packages/jamdict_data/jamdict.db',
        '/usr/lib/python3/dist-packages/jamdict_data/jamdict.db',
    ]
    try:
        import jamdict_data
        pkg = os.path.dirname(jamdict_data.__file__)
        candidates.insert(0, os.path.join(pkg, 'jamdict.db'))
    except Exception:
        pass
    for c in candidates:
        if os.path.isfile(c):
            return c
    raise FileNotFoundError('jamdict.db not found; pip install jamdict-data')

DB = None  # resolved in main()
ROOT = os.path.join(os.path.dirname(__file__), '..')
OFFICIAL = os.path.join(ROOT, 'data', 'official')
OUT_SERVER = os.path.join(ROOT, 'src', 'server', 'data')
TARGET = 1000
SEED = 20260916

KATAKANA_START, KATAKANA_END = 0x30A1, 0x30F6

LEVELS = [
    # key, label, files(new kanji)
    ('K10', '10級', ['K10']),
    ('K09', '9級', ['K09']),
    ('K08', '8級', ['K08']),
    ('K07', '7級', ['K07']),
    ('K06', '6級', ['K06']),
    ('K05', '5級', ['K05']),
    ('K04', '4級', ['K04a', 'K04b']),
    ('K03', '3級', ['K03a', 'K03b']),
    ('KP2', '準2級', ['KP2a', 'KP2b']),
    ('K02', '2級', []),          # + 常用漢字の残り185字
    ('KP1', '準1級', []),        # + JIS第1水準の非常用漢字 (≈3000字)
    ('K01', '1級', []),          # + JIS第2水準 (≈6000字)
]
N_LEVELS = len(LEVELS)

KANJI_RE = re.compile(r'^[\u4E00-\u9FFF\u3005]{1,4}[\u3041-\u309F]{0,3}$')
KANA_RE = re.compile(r'^[\u3041-\u309Fー]+$')
HAN_RE = re.compile(r'[\u4E00-\u9FFF\u3005]')


def kata_to_hira(s):
    out = []
    for ch in s:
        o = ord(ch)
        if KATAKANA_START <= o <= KATAKANA_END:
            out.append(chr(o - 0x60))
        else:
            out.append(ch)
    return ''.join(out)


def clean_kanji_reading(v):
    v = v.replace('.', '').replace('-', '')
    v = kata_to_hira(v)
    if not KANA_RE.match(v):
        return None
    return v


def mora_len(s):
    return len(s)


# ---------------------------------------------------------------- pools
def load_pools(cur):
    pools = []
    cum = set()
    for key, label, files in LEVELS:
        if files:
            for f in files:
                txt = open(os.path.join(OFFICIAL, f + '.txt'), encoding='utf-8').read()
                chars = HAN_RE.findall(txt)
                assert len(chars) == len(set(chars)), f'{f}: duplicates'
                cum |= set(chars)
        pools.append({'key': key, 'label': label, 'cum': set(cum), 'new': set()})
    for i, p in enumerate(pools):
        p['new'] = p['cum'] - (pools[i - 1]['cum'] if i else set())

    # 2級: rest of 常用漢字 (185)
    jouyou = set(r[0] for r in cur.execute(
        "SELECT literal FROM character WHERE CAST(grade AS INTEGER) BETWEEN 1 AND 8"))
    for i in (9, 10, 11):
        pools[i]['cum'] |= jouyou
    pools[9]['new'] = pools[9]['cum'] - pools[8]['cum']

    # 準1級: + JIS level-1 kanji (区16-47) up to ~3000
    jis_rows = {}
    for lit, val in cur.execute(
            "SELECT c.literal, cp.value FROM character c JOIN codepoint cp "
            "ON cp.cid=c.ID WHERE cp.cp_type='jis208'"):
        try:
            row = int(val.split('-')[1])
        except Exception:
            continue
        jis_rows[lit] = row
    freq = dict(cur.execute("SELECT literal, freq FROM character WHERE freq IS NOT NULL"))

    pre1_target = 3000
    cand = [(int(freq.get(l, 99999)), l) for l, row in jis_rows.items()
            if 16 <= row <= 47 and l not in pools[9]['cum']]
    cand.sort(key=lambda t: (t[0], t[1]))
    take = set()
    for _, l in cand:
        if len(pools[9]['cum']) + len(take) >= pre1_target:
            break
        take.add(l)
    pools[10]['cum'] |= take
    pools[10]['new'] = pools[10]['cum'] - pools[9]['cum']

    # 1級: + JIS level-2 (区48-94)
    take2 = set(l for l, row in jis_rows.items() if row >= 48 and l not in pools[10]['cum'])
    pools[11]['cum'] = pools[10]['cum'] | take2
    pools[11]['new'] = pools[11]['cum'] - pools[10]['cum']
    return pools


# ---------------------------------------------------------------- kanjidic2
def load_kanjidic(cur):
    """char -> {'on': [..], 'kun': [..], 'grade': int|None, 'freq': int|None, 'jis_row': int|None}"""
    info = defaultdict(lambda: {'on': [], 'kun': [], 'grade': None, 'freq': None, 'jis_row': None})
    for lit, g, f in cur.execute("SELECT literal, grade, freq FROM character"):
        info[lit]['grade'] = int(g) if g else None
        info[lit]['freq'] = int(f) if f else None
    for lit, val in cur.execute(
            "SELECT c.literal, cp.value FROM character c JOIN codepoint cp ON cp.cid=c.ID "
            "WHERE cp.cp_type='jis208'"):
        try:
            info[lit]['jis_row'] = int(val.split('-')[1])
        except Exception:
            pass
    for lit, rtype, val in cur.execute(
            "SELECT c.literal, rd.r_type, rd.value FROM rm_group rg "
            "JOIN character c ON c.ID=rg.cid JOIN reading rd ON rd.gid=rg.ID "
            "WHERE rd.r_type IN ('ja_on','ja_kun')"):
        r = clean_kanji_reading(val)
        if not r:
            continue
        if r not in info[lit]['on' if rtype == 'ja_on' else 'kun']:
            info[lit]['on' if rtype == 'ja_on' else 'kun'].append(r)
    return info


# ---------------------------------------------------------------- jmdict
PRI_RANK = {'news1': 0, 'ichi1': 0, 'spec1': 1, 'gai1': 2,
            'news2': 3, 'ichi2': 3, 'spec2': 4, 'gai2': 5}


def pri_score(tags):
    best = 99
    for t in tags:
        if t in PRI_RANK:
            best = min(best, PRI_RANK[t])
        elif t.startswith('nf'):
            try:
                best = min(best, 10 + int(t[2:]) // 4)
            except ValueError:
                pass
    return best


BAD_TAIL2 = {'って', 'った', 'んで', 'んだ', 'ます', 'ませ', 'まし', 'せん',
             'ない', 'なく', 'れば', 'よう', 'まい', 'すぎ', 'けれ',
             'たら', 'たり', 'だら', 'だり'}
BAD_TAIL1 = set('てただでばにのはがもよねなわょぁぃぅぇぉっが')


def okurigana_ok(tail):
    if not tail:
        return True
    if len(tail) >= 2 and tail[-2:] in BAD_TAIL2:
        return False
    if tail[-1] in BAD_TAIL1:
        return False
    return True


def load_words(cur):
    """yield (word, reading, score, all_readings, bad_flag)"""
    krows = defaultdict(list)   # idseq -> [(ID, text, pri, bad)]
    for kid, idseq, text in cur.execute("SELECT ID, idseq, text FROM Kanji"):
        krows[idseq].append([kid, text, 99, False])
    bad = set(r[0] for r in cur.execute("SELECT kid FROM KJI"))
    for kid, text in cur.execute("SELECT kid, text FROM KJP"):
        for row in krows.get(0, []):
            pass
    # attach pri
    primap = defaultdict(list)
    for kid, text in cur.execute("SELECT kid, text FROM KJP"):
        primap[kid].append(text)
    aprimap = defaultdict(list)
    for kid, text in cur.execute("SELECT kid, text FROM KNP"):
        aprimap[kid].append(text)
    for idseq, rows in krows.items():
        for row in rows:
            row[2] = pri_score(primap.get(row[0], []))
            row[3] = row[0] in bad
    arows = defaultdict(list)   # idseq -> [(ID, text, pri, nokanji)]
    for aid, idseq, text, nok in cur.execute(
            "SELECT ID, idseq, text, nokanji FROM Kana"):
        arows[idseq].append([aid, text, 99, nok])
    for idseq, rows in arows.items():
        for row in rows:
            row[2] = pri_score(aprimap.get(row[0], []))
    out = []
    for idseq in krows:
        ks = [r for r in krows[idseq] if not r[3] and KANJI_RE.match(r[1])]
        if not ks:
            continue
        ks.sort(key=lambda r: (r[2], len(r[1])))
        ktext, kscore = ks[0][1], ks[0][2]
        m = re.match(r'^([\u4E00-\u9FFF\u3005]+)(.*)$', ktext)
        if m and not okurigana_ok(m.group(2)):
            continue
        kana_all = [r for r in arows.get(idseq, []) if not r[3] and KANA_RE.match(r[1])]
        if not kana_all:
            continue
        kana_all.sort(key=lambda r: (r[2], len(r[1])))
        primary = kana_all[0]
        score = max(kscore, primary[2])
        readings = list(dict.fromkeys(r[1] for r in kana_all))
        out.append((ktext, primary[1], score, readings))
    return out


# ---------------------------------------------------------------- assignment
def word_pool_ok(word, pool):
    for ch in HAN_RE.findall(word):
        if ch not in pool:
            return False
    return True


def assign_words(words, pools):
    """word -> level index (lowest pool that contains all kanji)"""
    per_level = defaultdict(list)
    for word, reading, score, readings in words:
        for i, p in enumerate(pools):
            if word_pool_ok(word, p['cum']):
                per_level[i].append((word, reading, score, readings))
                break
    return per_level


# ---------------------------------------------------------------- romaji helper (Python版 Romaji.luau) — 重複排除用
_BASE_ROMAJI = {
    "あ":"a","い":"i","う":"u","え":"e","お":"o",
    "か":"ka","き":"ki","く":"ku","け":"ke","こ":"ko",
    "が":"ga","ぎ":"gi","ぐ":"gu","げ":"ge","ご":"go",
    "さ":"sa","し":"shi","す":"su","せ":"se","そ":"so",
    "ざ":"za","じ":"ji","ず":"zu","ぜ":"ze","ぞ":"zo",
    "た":"ta","ち":"chi","つ":"tsu","て":"te","と":"to",
    "だ":"da","ぢ":"ji","づ":"zu","で":"de","ど":"do",
    "な":"na","に":"ni","ぬ":"nu","ね":"ne","の":"no",
    "は":"ha","ひ":"hi","ふ":"fu","へ":"he","ほ":"ho",
    "ば":"ba","び":"bi","ぶ":"bu","べ":"be","ぼ":"bo",
    "ぱ":"pa","ぴ":"pi","ぷ":"pu","ぺ":"pe","ぽ":"po",
    "ま":"ma","み":"mi","む":"mu","め":"me","も":"mo",
    "や":"ya","ゆ":"yu","よ":"yo",
    "ら":"ra","り":"ri","る":"ru","れ":"re","ろ":"ro",
    "わ":"wa","ゐ":"i","ゑ":"e","を":"o","ん":"n","ゔ":"vu",
    "ぁ":"a","ぃ":"i","ぅ":"u","ぇ":"e","ぉ":"o","ゃ":"ya","ゅ":"yu","ょ":"yo","ゎ":"wa",
}
_COMBO_ROMAJI = {
    "きゃ":"kya","きゅ":"kyu","きょ":"kyo",
    "ぎゃ":"gya","ぎゅ":"gyu","ぎょ":"gyo",
    "しゃ":"sha","しゅ":"shu","しょ":"sho",
    "じゃ":"ja","じゅ":"ju","じょ":"jo",
    "ちゃ":"cha","ちゅ":"chu","ちょ":"cho",
    "ぢゃ":"ja","ぢゅ":"ju","ぢょ":"jo",
    "にゃ":"nya","にゅ":"nyu","にょ":"nyo",
    "ひゃ":"hya","ひゅ":"hyu","ひょ":"hyo",
    "びゃ":"bya","びゅ":"byu","びょ":"byo",
    "ぴゃ":"pya","ぴゅ":"pyu","ぴょ":"pyo",
    "みゃ":"mya","みゅ":"myu","みょ":"myo",
    "りゃ":"rya","りゅ":"ryu","りょ":"ryo",
    "ふぁ":"fa","ふぃ":"fi","ふぇ":"fe","ふぉ":"fo",
    "うぃ":"wi","うぇ":"we","うぉ":"wo",
    "しぇ":"she","じぇ":"je","ちぇ":"che",
    "てぃ":"ti","でぃ":"di","とぅ":"tu","どぅ":"du",
    "つぁ":"tsa","つぃ":"tsi","つぇ":"tse","つぉ":"tso",
    "ゔぁ":"va","ゔぃ":"vi","ゔぇ":"ve","ゔぉ":"vo",
}
_ALT_ROMAJI = {"ぢ":"di","づ":"du"}
_ALT_COMBO_ROMAJI = {"ぢゃ":"dya","ぢゅ":"dyu","ぢょ":"dyo"}
_SMALL = set(["ぁ","ぃ","ぅ","ぇ","ぉ","ゃ","ゅ","ょ","ゎ"])
_VOWELS = set(["a","i","u","e","o"])
_N_APO = set(["あ","い","う","え","お","や","ゆ","よ","ぁ","ぃ","ぅ","ぇ","ぉ","ゃ","ゅ","ょ","ゎ"])

def _kana_to_romaji(kana, alt=False):
    cs = list(kana)  # each char is 1 kana (all 3-byte but Python handles)
    # Actually need to split correctly but kana are single codepoints so list works
    out = []
    i = 0
    n = len(cs)
    def syllable_at(idx):
        if idx+1 < n:
            two = cs[idx] + cs[idx+1]
            if alt and two in _ALT_COMBO_ROMAJI:
                return _ALT_COMBO_ROMAJI[two], 2
            if two in _COMBO_ROMAJI:
                return _COMBO_ROMAJI[two], 2
        ch = cs[idx]
        if ch == "ん":
            nxt = cs[idx+1] if idx+1 < n else None
            if nxt and nxt in _N_APO:
                return "n'",1
            return "n",1
        if alt and ch in _ALT_ROMAJI:
            return _ALT_ROMAJI[ch],1
        return _BASE_ROMAJI.get(ch, ch),1
    while i < n:
        c = cs[i]
        if c == "っ" or c == "ッ":
            nxt = cs[i+1] if i+1<n else None
            if nxt and nxt not in _SMALL and nxt not in ("ー","っ","ッ"):
                r,_ = syllable_at(i+1)
                if r:
                    if r.startswith("ch"):
                        out.append("t")
                    else:
                        k = r[0]
                        if k not in _VOWELS:
                            if k == "n" and alt:
                                out.append("n'")
                            else:
                                out.append(k)
            i+=1
        elif c == "ー":
            prev = "".join(out)
            v=""
            for ch in reversed(prev):
                if ch in _VOWELS:
                    v=ch
                    break
            out.append(v)
            i+=1
        else:
            r, used = syllable_at(i)
            out.append(r)
            i+=used
    return "".join(out)

def _romaji_many(kana_list):
    out=[]
    used={}
    for idx, kana in enumerate(kana_list):
        r=_kana_to_romaji(kana)
        if r in used:
            # try to move previous to alt
            for j in range(idx):
                if out[j]==r:
                    alt=_kana_to_romaji(kana_list[j], True)
                    if alt!=r and alt not in used:
                        used.pop(out[j],None)
                        out[j]=alt
                        used[alt]=True
                        break
        if r in used:
            alt=_kana_to_romaji(kana, True)
            if alt!=r and alt not in used:
                r=alt
        out.append(r)
        used[r]=True
    return out

# ---------------------------------------------------------------- distractors
# 誤答は二値だけ: 「ミス」(同じ漢字の別の音/訓への入れ替え) か 「それ以外」(同級の実在読み)。
# 加点はしない。濁点を機械的に1文字ずらす連濁捏造 (いちにち→いぢにち) もしない。
# 一日なら ひとひ / ひとにち、校なら こう↔きょう のような音訓の取り違えがミス。

_VERBISH_KUN_TAIL = set('いるすくむぶぬうつし')


def _kanji_readings(kj, kan):
    info = kj.get(kan) or {}
    return list(dict.fromkeys(info.get('on', []) + info.get('kun', [])))


def _kun_ok_in_compound(kj, kan, alt, n_kanji, tail):
    """熟語で動詞・形容詞の活用訓 (あおい / さだめる) は不自然なので除外。"""
    kuns = (kj.get(kan) or {}).get('kun', [])
    if alt not in kuns:
        return True
    if n_kanji >= 2 and not tail and len(alt) > 2 and alt[-1] in _VERBISH_KUN_TAIL:
        return False
    return True


def _find_segmentation(kanjis, answer_core, kj):
    # kanjis: list of kanji characters (with 々 resolved)
    # answer_core: kana string for kanji part only
    # returns list of segments or None
    n = len(kanjis)
    # memoization
    memo = {}
    def dfs(idx, pos):
        key = (idx,pos)
        if key in memo:
            return memo[key]
        if idx==n:
            if pos==len(answer_core):
                return []
            else:
                memo[key]=None
                return None
        kan = kanjis[idx]
        readings = kj.get(kan, {}).get('on', []) + kj.get(kan, {}).get('kun', [])
        # 並びは長い順→一致しやすい
        readings = sorted(set(readings), key=lambda x: (-len(x), x))
        # 試す: answer_core[pos:] が reading で始まるもの
        for r in readings:
            if answer_core.startswith(r, pos):
                rest = dfs(idx+1, pos+len(r))
                if rest is not None:
                    memo[key]=[r]+rest
                    return memo[key]
        memo[key]=None
        return None
    return dfs(0,0)

def _add_reading(out, cand, answer):
    if cand and cand != answer and 1 <= len(cand) <= 8 and KANA_RE.match(cand):
        out.add(cand)


def _realistic_variants(word, answer, kj, rng=None):
    """同じ漢字の別の音/訓へ入れ替えた読みだけを返す (機械的な濁点ずらしはしない)。"""
    out = set()
    m = re.match(r'^([\u4E00-\u9FFF々]+)([\u3041-\u309F]*)$', word)
    if not m:
        return []
    kanji_str, tail = m.groups()
    kanjis = list(kanji_str)
    for i, ch in enumerate(kanjis):
        if ch == '々' and i > 0:
            kanjis[i] = kanjis[i - 1]
    answer_core = answer
    if tail and answer.endswith(tail):
        answer_core = answer[:-len(tail)]
    elif tail:
        answer_core = answer
        tail = ""
    segs = _find_segmentation(kanjis, answer_core, kj) if kanjis else None
    n_kanji = len(kanjis)
    if segs and len(segs) == n_kanji:
        alt_lists = []
        for idx, kan in enumerate(kanjis):
            orig = segs[idx]
            alts = [orig]
            for alt in _kanji_readings(kj, kan):
                if alt == orig:
                    continue
                if not _kun_ok_in_compound(kj, kan, alt, n_kanji, tail):
                    continue
                alts.append(alt)
            alt_lists.append(alts)
        # 2字熟語は音訓の組み合わせ全部 (一日→ひとひ / ひとにち)。3字以上は1字ずつ入れ替え。
        if n_kanji <= 2:
            for combo in product(*alt_lists):
                if tuple(combo) == tuple(segs):
                    continue
                _add_reading(out, "".join(combo) + tail, answer)
        else:
            for idx, alts in enumerate(alt_lists):
                for alt in alts:
                    if alt == segs[idx]:
                        continue
                    new_core = "".join(segs[:idx] + [alt] + segs[idx + 1:])
                    _add_reading(out, new_core + tail, answer)
    else:
        kanji_chars = HAN_RE.findall(word)
        if kanji_chars:
            first = kanji_chars[0]
            for orig in _kanji_readings(kj, first):
                if answer.startswith(orig) and 0 < len(orig) < len(answer):
                    for alt in _kanji_readings(kj, first):
                        if alt != orig:
                            _add_reading(out, alt + answer[len(orig):], answer)
            last = kanji_chars[-1]
            for orig in _kanji_readings(kj, last):
                if answer.endswith(orig) and 0 < len(orig) < len(answer):
                    for alt in _kanji_readings(kj, last):
                        if alt != orig:
                            _add_reading(out, answer[:-len(orig)] + alt, answer)
    if n_kanji == 1:
        for alt in _kanji_readings(kj, kanjis[0]):
            _add_reading(out, alt, answer)
    # set の反復順は PYTHONHASHSEED 依存なので sorted で固定
    return sorted(c for c in out if c != answer)


def pick_distractors(answer, pool_readings, forbid, synthetic_pool, rng, n=3):
    """ミス (音訓入れ替え) を先にランダム採用。足りなければ同級の実在読み。加点なし。"""
    used = set([answer]) | set(forbid)
    picked = []

    def take_from(source, delta):
        cands = []
        seen = set()
        for r in source:
            if r in used or r in seen:
                continue
            if not KANA_RE.match(r):
                continue
            if abs(len(r) - len(answer)) > delta:
                continue
            cands.append(r)
            seen.add(r)
        cands.sort()
        rng.shuffle(cands)
        for c in cands:
            if len(picked) >= n:
                return
            rom = _romaji_many([answer] + picked + [c])
            if len(set(rom)) != len(rom):
                continue
            picked.append(c)
            used.add(c)

    misses = list(synthetic_pool)
    others = list(pool_readings)
    for delta in (8,):  # 音訓入れ替えは長さが多少違ってもミスとして採用 (ひとひ vs いちにち)
        take_from(misses, delta)
        if len(picked) >= n:
            return picked[:n]
    for delta in (1, 2, 8):
        take_from(others, delta)
        if len(picked) >= n:
            return picked[:n]
    return picked[:n]


# ---------------------------------------------------------------- synthesis
def make_question(prompt, answer, distractors, qtype):
    ds = list(dict.fromkeys(distractors))[:3]
    assert len(ds) == 3
    return {'p': prompt, 'a': answer, 'd': ds, 't': qtype}


def synthesize_level(li, pools, kj, words_by_level, used_global, used_prompt_level,
                    pool_readings, rng):
    pool = pools[li]['cum']
    questions = []

    def try_add(prompt, answer, distractors, qtype, forbidden):
        if (prompt, answer) in used_global or prompt in used_prompt_level:
            return False
        ds = []
        for d in distractors:
            if d == answer or d in forbidden or d in ds:
                continue
            ds.append(d)
            if len(ds) == 3:
                break
        if len(ds) < 3:
            return False
        q = make_question(prompt, answer, ds, qtype)
        questions.append(q)
        used_global.add((prompt, answer))
        used_prompt_level.add(prompt)
        pool_ans.append(answer)
        return True

    pool_ans = pool_readings.setdefault(li, [])
    wlist = words_by_level.get(li, [])
    a_max = 10 if li < 8 else 22  # 高レベルは nf タグまで許可
    pri_words = [w for w in wlist if w[2] <= a_max]
    nonpri_words = [w for w in wlist if w[2] > a_max]
    pri_words.sort(key=lambda w: (w[2], len(HAN_RE.findall(w[0])) != 2, len(w[0])))
    nonpri_words.sort(key=lambda w: (len(HAN_RE.findall(w[0])) != 2, len(w[0])))
    covered = set()

    def kanji_covered(word):
        for ch in HAN_RE.findall(word):
            if ch != '々':
                covered.add(ch)

    def word_pass(words, budget):
        n = 0
        for word, reading, score, readings in words:
            if n >= budget or len(questions) >= TARGET:
                break
            if not (1 <= len(reading) <= 7):
                continue
            forbidden = set(r for r in readings if r != reading)
            syn = _realistic_variants(word, reading, kj)
            distr = pick_distractors(reading, pool_ans, forbidden, syn, rng, 3)
            if try_add(word, reading, distr, 'w', forbidden):
                n += 1
                kanji_covered(word)
        return n

    def s_questions(kanji_iter):
        n = 0
        for ch in kanji_iter:
            if len(questions) >= TARGET:
                break
            if ch == '々':
                continue
            info = kj.get(ch)
            if not info:
                continue
            reads = info['kun'] + info['on']
            if not reads:
                continue
            times = sum(1 for (p, a) in used_global if p == ch)
            idx = min(times, len(reads) - 1)
            answer = reads[idx]
            if not (1 <= len(answer) <= 6):
                continue
            forbidden = set(reads) - {answer}
            syn = _realistic_variants(ch, answer, kj)
            distr = pick_distractors(answer, pool_ans, forbidden, syn, rng, 3)
            if try_add(ch, answer, distr, 's', forbidden):
                n += 1
        return n

    # A: common (tagged) words - reserve slots for new-kanji S questions
    budget = TARGET - (len(pools[li]['new']) if li < 10 else TARGET // 100)
    word_pass(pri_words, budget)
    # B: single-kanji questions - guarantee every new kanji gets asked
    if li < 10:
        if li <= 5:
            # 小学範囲: 単漢字の読みを全新出漢字に (漢検らしさ)
            unc_new = sorted(pools[li]['new'])
        else:
            unc_new = [ch for ch in sorted(pools[li]['new']) if ch not in covered]
        rest = (set(pool) - pools[li]['new']) if li < 6 else set()
        unc_rest = [ch for ch in sorted(rest) if ch not in covered]
        s_questions(unc_new + unc_rest)
    # C: fill with untagged words (2-kanji first)
    word_pass(nonpri_words, TARGET)
    # D: top-up with extra readings of pool kanji (no S questions at 準1級/1級)
    if len(questions) < TARGET and li < 10:
        base = pools[li]['new'] if li >= 6 else set(pool)
        extra = [ch for ch in sorted(base, key=lambda c: rng.random())]
        for ch in extra:
            if len(questions) >= TARGET:
                break
            info = kj.get(ch)
            if not info:
                continue
            for answer in info['kun'] + info['on']:
                if len(questions) >= TARGET:
                    break
                if (ch, answer) in used_global or ch in used_prompt_level:
                    continue
                if not (1 <= len(answer) <= 6):
                    continue
                forbidden = set(info['kun'] + info['on']) - {answer}
                syn = _realistic_variants(ch, answer, kj)
                distr = pick_distractors(answer, pool_ans, forbidden, syn, rng, 3)
                try_add(ch, answer, distr, 's', forbidden)

    return questions


def main():
    rng = random.Random(SEED)
    os.makedirs(OUT_SERVER, exist_ok=True)
    db_path = _find_jamdict_db()
    db = sqlite3.connect(db_path)
    cur = db.cursor()
    print('loading pools...')
    pools = load_pools(cur)
    for p in pools:
        print(f"  {p['label']}: cum={len(p['cum'])} new={len(p['new'])}")
    print('loading kanjidic2...')
    kj = load_kanjidic(cur)
    print('loading jmdict words...')
    words = load_words(cur)
    print(f'  candidate words: {len(words)}')
    words_by_level = assign_words(words, pools)
    for i, p in enumerate(pools):
        print(f"  {p['label']}: {len(words_by_level.get(i, []))} words")

    used_global = set()
    all_q = {}
    pool_readings = {}
    for li in range(N_LEVELS):
        used_prompt_level = set()
        qs = synthesize_level(li, pools, kj, words_by_level, used_global,
                              used_prompt_level, pool_readings, rng)
        rng.shuffle(qs)
        all_q[pools[li]['key']] = qs
        nw = sum(1 for q in qs if q['t'] == 'w')
        ns = len(qs) - nw
        asked = set()
        for q in qs:
            for ch in HAN_RE.findall(q['p']):
                if ch != '々':
                    asked.add(ch)
        unasked = [ch for ch in pools[li]['new'] if ch not in asked]
        print(f"{pools[li]['label']}: {len(qs)} q (words={nw}, single={ns}), "
              f"new-kanji unasked={len(unasked)} {''.join(unasked[:20])}")

    # emit
    stats = {}
    for key, qs in all_q.items():
        stats[key] = {'count': len(qs)}
        path = os.path.join(OUT_SERVER, f'Questions_{key}.luau')
        with open(path, 'w', encoding='utf-8') as f:
            label = next(p['label'] for p in pools if p['key'] == key)
            f.write('--!nolint\n')
            f.write(f'-- Generated by tools/generate_questions.py - do not edit\n')
            f.write(f'-- 漢検{label} 読み問題 {len(qs)}問\n')
            f.write('return {\n')
            for q in qs:
                ds = ','.join('"%s"' % d for d in q['d'])
                f.write('{p="%s",a="%s",d={%s},t="%s"},\n' % (q['p'], q['a'], ds, q['t']))
            f.write('}\n')
        print(f'wrote {path} ({os.path.getsize(path)//1024} KB)')
    with open(os.path.join(ROOT, 'tools', 'stats.json'), 'w', encoding='utf-8') as f:
        json.dump(stats, f, ensure_ascii=False, indent=1)

    # samples for review
    for key, qs in all_q.items():
        print(f'--- {key} samples ---')
        for q in rng.sample(qs, 5):
            print(f'  {q["p"]} -> {q["a"]}  ({" / ".join(q["d"])})')


if __name__ == '__main__':
    main()
