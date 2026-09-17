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

DB = os.environ.get('JAMDICT_DB', '/usr/local/lib/python3.11/dist-packages/jamdict_data/jamdict.db')
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

# 漢字の常識的な音訓取り違えを固定する代表例。生成結果が辞書更新で
# 揺れても、一日・青年・定款のような「見た瞬間に意味が分かる」問題は守る。
PINNED_QUESTIONS = {
    'K10': [
        {'p': '一日', 'a': 'いちにち', 'd': ['ひとにち', 'いつにち', 'いちじつ'], 't': 'w'},
        {'p': '青年', 'a': 'せいねん', 'd': ['あおとし', 'あおねん', 'せいとし'], 't': 'w'},
    ],
    'K03': [
        {'p': '実施', 'a': 'じっし', 'd': ['じし', 'じつし', 'ぢっし'], 't': 'w'},
    ],
    'KP2': [
        {'p': '定款', 'a': 'ていかん', 'd': ['ていせん', 'じょうかん', 'さだかん'], 't': 'w'},
    ],
}

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


# ---------------------------------------------------------------- distractors
# 誤答は「同じ長さのランダムな読み」ではなく、濁点・促音・長音・近い音を
# 1箇所だけ取り違えた、漢検らしい near-miss を優先する。
CONFUSION_GROUPS = [
    'かが', 'きぎ', 'くぐ', 'けげ', 'こご', 'さざ', 'しじ', 'すず', 'せぜ', 'そぞ',
    'ただ', 'ちぢ', 'つづ', 'てで', 'とど', 'はばぱ', 'ひびぴ', 'ふぶぷ', 'へべぺ',
    'ほぼぽ', 'じぢ', 'ずづ', 'しち', 'すつ', 'せつ',
    'あいうえお', 'なにぬねの', 'まみむめも', 'らりるれろ', 'やゆよ', 'わをん',
]
CONFUSION = {}
SMALL_KANA = set('ぁぃぅぇぉゃゅょゎ')

def small_shape_ok(candidate, answer):
    candidate_shape = tuple((i, ch) for i, ch in enumerate(candidate) if ch in SMALL_KANA)
    answer_shape = tuple((i, ch) for i, ch in enumerate(answer) if ch in SMALL_KANA)
    return not candidate_shape or candidate_shape == answer_shape

for _group in CONFUSION_GROUPS:
    _chars = set(_group)
    for _ch in _chars:
        CONFUSION[_ch] = _chars


def confusing_variants(reading):
    """かな1モーラだけを取り違える候補。全てかなのままなので表示上も読み。"""
    out = []
    chars = list(reading)
    small_to_large = {'ぁ': 'あ', 'ぃ': 'い', 'ぅ': 'う', 'ぇ': 'え', 'ぉ': 'お',
                      'ゃ': 'や', 'ゅ': 'ゆ', 'ょ': 'よ', 'ゎ': 'わ'}

    # 促音の脱落 / 「つ」と読む誤りは最優先。きっさ→きさ・きつさ。
    for i, ch in enumerate(chars):
        if ch == 'っ':
            for replacement in ('', 'つ'):
                candidate = reading[:i] + replacement + reading[i + 1:]
                if candidate not in out:
                    out.append(candidate)

    # 先に濁点・母音の取り違えを並べる。促音の二重化は最後にする。
    for i, ch in enumerate(chars):
        if ch == 'っ':
            continue
        for alt in CONFUSION.get(ch, ()):
            if alt != ch:
                candidate = ''.join(chars[:i] + [alt] + chars[i + 1:])
                if candidate not in out:
                    out.append(candidate)
        if ch in small_to_large:
            candidate = ''.join(chars[:i] + [small_to_large[ch]] + chars[i + 1:])
            if candidate not in out:
                out.append(candidate)

    for old, new in (('おう', 'おお'), ('おお', 'おう'), ('えい', 'ええ'), ('ええ', 'えい')):
        if old in reading:
            candidate = reading.replace(old, new, 1)
            if candidate not in out:
                out.append(candidate)

    # 促音の新規挿入は日本語話者がしない人工的な誤答になるため生成しない。
    return out


def confusing_distance(a, b):
    """濁点違いは安く、一般の置換/挿入は少し高くする編集距離。"""
    aa, bb = list(a), list(b)
    previous = list(range(len(bb) + 1))
    for i, x in enumerate(aa, 1):
        current = [i]
        for j, y in enumerate(bb, 1):
            if x == y:
                substitution = 0
            elif CONFUSION.get(x) is CONFUSION.get(y) and CONFUSION.get(x):
                substitution = 0.45
            else:
                substitution = 1.0
            current.append(min(current[-1] + 0.82, previous[j] + 0.82,
                               previous[j - 1] + substitution))
        previous = current
    return previous[-1]


def word_reading_segments(word, reading, kj):
    """漢字ごとの on/kun 読みで、実際の正解を分割できる候補を返す。"""
    chars = HAN_RE.findall(word)
    if len(chars) < 2 or len(chars) != len(word):
        return []
    options = []
    for ch in chars:
        info = kj.get(ch)
        if not info:
            return []
        reads = list(dict.fromkeys(info['on'] + info['kun']))
        options.append([r for r in reads if r])
    out = []

    def visit(index, offset, segments):
        if index == len(options):
            if offset == len(reading):
                out.append(list(segments))
            return
        for candidate in options[index]:
            if reading.startswith(candidate, offset):
                segments.append(candidate)
                visit(index + 1, offset + len(candidate), segments)
                segments.pop()

    visit(0, 0, [])
    return out


def semantic_distractors(word, reading, kj, forbid, rng, limit=6):
    """漢字ごとの音訓の取り違えを作る (一日→ひとにち、青年→あおとし)。"""
    scored = []
    chars = HAN_RE.findall(word)
    segments_list = word_reading_segments(word, reading, kj)
    if len(chars) == 1:
        info = kj.get(chars[0]) or {}
        kun = info.get('kun', [])
        for alternative in list(dict.fromkeys(kun + info.get('on', []))):
            if alternative == reading or len(alternative) > len(reading) + 1:
                continue
            if len(alternative) == 1 and len(reading) >= 2:
                continue
            if alternative in forbid or not KANA_RE.match(alternative):
                continue
            kind_priority = 0 if alternative in kun else 1
            scored.append(((abs(len(alternative) - len(reading)), kind_priority, alternative), alternative))
    for segments in segments_list:
        for i, ch in enumerate(chars):
            info = kj.get(ch) or {}
            kun = info.get('kun', [])
            alternatives = list(dict.fromkeys(kun + info.get('on', [])))
            for alternative in alternatives:
                current = segments[i]
                # 熟語では活用形や一文字だけの極端な短縮を誤読にしない。
                if alternative == current or len(alternative) > len(current):
                    continue
                if len(alternative) == 1 and len(current) >= 2:
                    continue
                candidate = ''.join(segments[:i] + [alternative] + segments[i + 1:])
                if candidate == reading or candidate in forbid:
                    continue
                if 1 <= len(candidate) <= len(reading) + 1 and KANA_RE.match(candidate):
                    kind_priority = 0 if alternative in kun else 1
                    score = (abs(len(candidate) - len(reading)), kind_priority, candidate)
                    scored.append((score, candidate))
        # 2文字以上を同時に訓読みにすると、人が実際にやりがちな読み順になる。
        if len(chars) >= 2:
            for i in range(len(chars)):
                for j in range(i + 1, len(chars)):
                    ai = (kj.get(chars[i]) or {}).get('kun', [])
                    aj = (kj.get(chars[j]) or {}).get('kun', [])
                    if not ai or not aj:
                        continue
                    candidate_segments = list(segments)
                    if len(ai[0]) == len(segments[i]):
                        candidate_segments[i] = ai[0]
                    if len(aj[0]) == len(segments[j]):
                        candidate_segments[j] = aj[0]
                    candidate = ''.join(candidate_segments)
                    if candidate != reading and candidate not in forbid and KANA_RE.match(candidate):
                        scored.append(((abs(len(candidate) - len(reading)), 0, candidate), candidate))
    out = []
    for _, candidate in sorted(scored, key=lambda item: item[0]):
        if candidate not in out:
            out.append(candidate)
        if len(out) >= limit:
            break
    return out


def sokuon_shape_ok(answer, candidate):
    """促音は脱落/「つ」読みだけを許可し、挿入・二重化を捨てる。"""
    if 'っっ' in candidate:
        return False
    if candidate.count('っ') > answer.count('っ'):
        return False
    if 'っ' not in answer and (candidate.startswith('っ') or candidate.endswith('っ')):
        return False
    return True


def near_miss_distractors(reading, pool_readings, forbid, rng, limit=3):
    direct = [x for x in confusing_variants(reading)
              if sokuon_shape_ok(reading, x) and x != reading and x not in forbid and small_shape_ok(x, reading) and KANA_RE.match(x)]
    rng.shuffle(direct)
    scored = []
    for candidate in pool_readings:
        if (not sokuon_shape_ok(reading, candidate) or candidate in forbid or
                candidate == reading or candidate in direct or not small_shape_ok(candidate, reading)):
            continue
        if abs(len(candidate) - len(reading)) > 2:
            continue
        score = confusing_distance(reading, candidate)
        if score <= 2.15:
            scored.append((score, abs(len(candidate) - len(reading)), candidate))
    rng.shuffle(scored)
    scored.sort(key=lambda x: (x[0], x[1]))
    # 本物の辞書読みを優先し、足りない時だけ1モーラの合成 near-miss を使う。
    out = [x[2] for x in scored[:limit]]
    for candidate in direct:
        if len(out) >= limit:
            break
        if candidate not in out:
            out.append(candidate)
    return out[:limit]


def swap_distractors(word, reading, kj, level_pool_answers, forbid, rng, limit=3):
    """reading-swap: replace prefix/suffix on-yomi of a kanji with its alternate on-yomi."""
    cands = []
    kanji_chars = HAN_RE.findall(word)
    if kanji_chars and kanji_chars[0] in kj:
        first = kj[kanji_chars[0]]
        for o in first['on']:
            if reading.startswith(o) and len(o) < len(reading):
                for o2 in first['on']:
                    if o2 != o and len(o2) == len(o):
                        cands.append(o2 + reading[len(o):])
                break
    if kanji_chars and kanji_chars[-1] in kj:
        last = kj[kanji_chars[-1]]
        for o in last['on']:
            if reading.endswith(o) and len(o) < len(reading):
                for o2 in last['on']:
                    if o2 != o and len(o2) == len(o):
                        cands.append(reading[:-len(o)] + o2)
                break
    out = []
    for c in cands:
        if (sokuon_shape_ok(reading, c) and c != reading and c not in forbid
                and c not in out and 1 <= len(c) <= 8):
            out.append(c)
    return out


def pick_random_readings(reading, pool_readings, forbid, rng, n, length_delta=1):
    L = len(reading)
    cands = [r for r in pool_readings
             if (sokuon_shape_ok(reading, r) and abs(len(r) - L) <= length_delta
                 and r != reading and r not in forbid)]
    rng.shuffle(cands)
    return cands[:n]


# 英語UIのローマ字で同じ表示になる候補を生成段階でも除外する。
# じ/ぢ・ず/づは Romaji.convertMany 側で救済するが、他の衝突はここで防ぐ。
ROMAJI_BASE = {
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
    'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
    'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
    'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
    'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
    'や': 'ya', 'ゆ': 'yu', 'よ': 'yo', 'ら': 'ra', 'り': 'ri',
    'る': 'ru', 'れ': 're', 'ろ': 'ro', 'わ': 'wa', 'を': 'o', 'ん': 'n',
}
ROMAJI_COMBO = {
    'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo', 'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
    'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho', 'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
    'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho', 'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
    'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo', 'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
    'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo', 'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
    'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
}


def romaji_key(kana):
    chars = list(kana)
    out = []
    i = 0
    while i < len(chars):
        if chars[i] == 'っ':
            if i + 1 < len(chars):
                nxt = ROMAJI_COMBO.get(''.join(chars[i + 1:i + 3]), ROMAJI_BASE.get(chars[i + 1], ''))
                if nxt and not nxt[0] in 'aiueo':
                    out.append('t' if nxt.startswith('ch') else nxt[0])
            i += 1
            continue
        if i + 1 < len(chars) and ''.join(chars[i:i + 2]) in ROMAJI_COMBO:
            out.append(ROMAJI_COMBO[''.join(chars[i:i + 2])])
            i += 2
            continue
        if chars[i] == 'ー':
            previous = ''.join(out)
            out.append(next((c for c in reversed(previous) if c in 'aiueo'), ''))
        else:
            out.append(ROMAJI_BASE.get(chars[i], chars[i]))
        i += 1
    return ''.join(out)


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
        used_romaji = {romaji_key(answer)}
        for d in distractors:
            d_key = romaji_key(d)
            if (not sokuon_shape_ok(answer, d) or d == answer or d in forbidden
                    or d in ds or d_key in used_romaji):
                continue
            ds.append(d)
            used_romaji.add(d_key)
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
            distr = semantic_distractors(word, reading, kj, forbidden, rng, 3)
            if len(distr) < 3:
                for candidate in confusing_variants(reading):
                    if candidate not in forbidden and candidate not in distr and small_shape_ok(candidate, reading):
                        distr.append(candidate)
                    if len(distr) >= 3:
                        break
            if len(distr) < 3:
                distr += near_miss_distractors(reading, pool_ans, forbidden, rng, 3 - len(distr))
            if len(distr) < 3:
                distr += swap_distractors(word, reading, kj, pool_ans, forbidden, rng)
            need = 3 - len(distr)
            if need > 0:
                distr += pick_random_readings(reading, pool_ans, forbidden, rng, need)
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
            distr = near_miss_distractors(answer, pool_ans, forbidden, rng)
            if len(distr) < 3:
                distr += pick_random_readings(answer, pool_ans, forbidden, rng, 3 - len(distr))
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
                distr = near_miss_distractors(answer, pool_ans, forbidden, rng)
                if len(distr) < 3:
                    distr += pick_random_readings(answer, pool_ans, forbidden, rng, 3 - len(distr))
                try_add(ch, answer, distr, 's', forbidden)

    return questions


def main():
    rng = random.Random(SEED)
    os.makedirs(OUT_SERVER, exist_ok=True)
    db = sqlite3.connect(DB)
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
        level_key = pools[li]['key']
        for pinned in PINNED_QUESTIONS.get(level_key, []):
            replaced = False
            for qi, existing in enumerate(qs):
                if existing['p'] == pinned['p']:
                    qs[qi] = pinned
                    replaced = True
                    break
            if not replaced:
                # 各級の問題数は常にTARGET問に保つ。
                qs[-1] = pinned
        rng.shuffle(qs)
        all_q[level_key] = qs
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
