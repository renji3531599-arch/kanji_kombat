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

DB = '/usr/local/lib/python3.11/dist-packages/jamdict_data/jamdict.db'
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

# ---------------------------------------------------------------- distractors — 超紛らわしい生成
# 4択すべてがパッと見で間違えやすい、漢検本番級のひっかけを再現する

# 濁点・半濁点の対応 (一文字差で激似にするため)
_DAKUTEN_MAP = {
    'か': ['が'], 'き': ['ぎ'], 'く': ['ぐ'], 'け': ['げ'], 'こ': ['ご'],
    'さ': ['ざ'], 'し': ['じ'], 'す': ['ず'], 'せ': ['ぜ'], 'そ': ['ぞ'],
    'た': ['だ'], 'ち': ['ぢ'], 'つ': ['づ'], 'て': ['で'], 'と': ['ど'],
    'は': ['ば', 'ぱ'], 'ひ': ['び', 'ぴ'], 'ふ': ['ぶ', 'ぷ'], 'へ': ['べ', 'ぺ'], 'ほ': ['ぼ', 'ぽ'],
    'が': ['か'], 'ぎ': ['き'], 'ぐ': ['く'], 'げ': ['け'], 'ご': ['こ'],
    'ざ': ['さ'], 'じ': ['し', 'ぢ'], 'ず': ['す', 'づ'], 'ぜ': ['せ'], 'ぞ': ['そ'],
    'だ': ['た'], 'ぢ': ['ち', 'じ'], 'づ': ['つ', 'ず'], 'で': ['て'], 'ど': ['と'],
    'ば': ['は', 'ぱ'], 'び': ['ひ', 'ぴ'], 'ぶ': ['ふ', 'ぷ'], 'べ': ['へ', 'ぺ'], 'ぼ': ['ほ', 'ぽ'],
    'ぱ': ['は', 'ば'], 'ぴ': ['ひ', 'び'], 'ぷ': ['ふ', 'ぶ'], 'ぺ': ['へ', 'べ'], 'ぽ': ['ほ', 'ぼ'],
}

def _lev(a, b):
    # かな同士のレーベンシュタイン距離 (短いのでDPで十分)
    n, m = len(a), len(b)
    dp = list(range(m+1))
    for i in range(1, n+1):
        ndp = [i] + [0]*m
        for j in range(1, m+1):
            cost = 0 if a[i-1] == b[j-1] else 1
            ndp[j] = min(dp[j]+1, ndp[j-1]+1, dp[j-1]+cost)
        dp = ndp
    return dp[m]

def _confusion_score(ans, cand):
    """高いほど紛らわしい (0-100)"""
    if cand == ans:
        return -999
    # 長さ差が大きいほど減点 (だが±1はむしろ加点:「長音1つ違い」は最強のひっかけ)
    ld = abs(len(ans)-len(cand))
    score = 50
    if ld == 0:
        score += 12
    elif ld == 1:
        score += 8
    else:
        score -= ld * 10
    # 編集距離が小さいほど加点
    d = _lev(ans, cand)
    if d == 1:
        score += 22
    elif d == 2:
        score += 14
    elif d == 3:
        score += 4
    else:
        score -= d * 4
    # 共通接頭辞/接尾辞
    pref = 0
    for i in range(min(len(ans), len(cand))):
        if ans[i]==cand[i]:
            pref+=1
        else:
            break
    suff = 0
    for i in range(1, min(len(ans), len(cand))+1):
        if ans[-i]==cand[-i]:
            suff+=1
        else:
            break
    score += pref*3 + suff*3
    # 促音・長音・拗音の有無だけ違うのは激似
    if 'っ' in ans or 'っ' in cand:
        if ans.replace('っ','') == cand.replace('っ',''):
            score += 18
    if ans.replace('う','').replace('ー','') == cand.replace('う','').replace('ー',''):
        score += 12
    # 濁点1文字違い
    diff_chars = sum(1 for a,c in zip(ans, cand) if a!=c)
    if diff_chars == 1 and len(ans)==len(cand):
        for a,c in zip(ans, cand):
            if a!=c and c in _DAKUTEN_MAP.get(a, []):
                score += 16
                break
    # 同じ語尾 (〜しゅう/〜じゅう, 〜こう/〜ごう など) は超紛らわしい
    if len(ans)>=2 and len(cand)>=2 and ans[-2:]==cand[-2:]:
        score += 6
    if len(ans)>=1 and len(cand)>=1 and ans[-1]==cand[-1]:
        score += 4
    return score

def _synthetic_variants(answer, rng):
    """回答から1モーラだけ捻った合成ひっかけを大量生成 (本物の読みらしく)"""
    out = set()
    n = len(answer)
    # 1) 濁点・半濁点フリップ
    for i,ch in enumerate(answer):
        for alt in _DAKUTEN_MAP.get(ch, []):
            cand = answer[:i] + alt + answer[i+1:]
            if KANA_RE.match(cand):
                out.add(cand)
    # 2) 促音 っ の挿入/削除/移動
    if 'っ' not in answer and n>=2:
        # 2文字目あたりにっを挿入
        for pos in (1,2):
            if pos < n:
                cand = answer[:pos] + 'っ' + answer[pos:]
                if 1 <= len(cand) <= 8 and KANA_RE.match(cand):
                    out.add(cand)
    if 'っ' in answer:
        out.add(answer.replace('っ','',1))
        # っの位置をずらす
        idx = answer.index('っ')
        if idx+1 < n:
            cand = answer[:idx] + answer[idx+1] + 'っ' + answer[idx+2:] if idx+2<=n else answer
            if KANA_RE.match(cand):
                out.add(cand)
    # 3) 長音 う/い の増減 (こう↔こお, せい↔せえ)
    for i,ch in enumerate(answer):
        if ch == 'う' and i>0:
            # うを削除
            cand = answer[:i] + answer[i+1:]
            if KANA_RE.match(cand):
                out.add(cand)
        if ch in ('か','さ','た','な','は','ま','や','ら','わ','が','ざ','だ','ば','ぱ'):
            # のばす: か→かあ みたいな? むしろ お段+う
            pass
    # お段 + う の有無 (きょう/きょお, そう/そお)
    if answer.endswith('う'):
        out.add(answer[:-1])
        out.add(answer[:-1] + 'ー')
    else:
        if n>=2 and answer[-2] in ('き','し','ち','に','ひ','み','り','ぎ','じ','び','ぴ','く','す','つ','ふ','ぐ','ず'):
            cand = answer + 'う'
            if KANA_RE.match(cand):
                out.add(cand)
    # 4) 拗音 ゃゅょ の増減
    small = {'ゃ','ゅ','ょ'}
    if any(c in small for c in answer):
        for c in small:
            if c in answer:
                out.add(answer.replace(c,'',1))
                out.add(answer.replace(c, {'ゃ':'や','ゅ':'ゆ','ょ':'よ'}[c],1))
    else:
        if n>=2:
            for c in ('ゃ','ゅ','ょ'):
                cand = answer[:1] + c + answer[1:]
                if KANA_RE.match(cand):
                    out.add(cand)
    # 5) 末尾1文字の母音違い (せい→せえ/せお)
    if n>=1:
        tail = answer[-1]
        vowel_map = {'あ':'い','い':'え','う':'お','え':'い','お':'う','か':'き','き':'け','く':'こ'}
        # 適当に近傍のひらがなに1文字置換
        for alt in ('あ','い','う','え','お','ん'):
            if alt != tail:
                cand = answer[:-1] + alt
                if KANA_RE.match(cand):
                    out.add(cand)
                break
    # 6) ん の挿入/削除
    if 'ん' in answer:
        out.add(answer.replace('ん','',1))
    else:
        if n>=2:
            cand = answer[:n//2] + 'ん' + answer[n//2:]
            if KANA_RE.match(cand):
                out.add(cand)
    # 7) ランダム1文字置換 (近傍ひらがな)
    # ひらがな一覧から1文字だけ違う候補を少しだけ
    hira = [chr(c) for c in range(ord('あ'), ord('ん')+1) if KANA_RE.match(chr(c))]
    for _ in range(6):
        pos = rng.randrange(n) if n else 0
        cand = answer[:pos] + rng.choice(hira) + answer[pos+1:]
        if cand != answer and KANA_RE.match(cand):
            out.add(cand)
    # 長さフィルタ
    out = {c for c in out if 1 <= len(c) <= 8 and c != answer}
    return list(out)

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
        if c != reading and c not in forbid and c not in out and 1 <= len(c) <= 8:
            out.append(c)
    return out

def pick_tricky_distractors(answer, pool_readings, forbid, synthetic_pool, rng, n=3):
    """プール+合成から最も紛らわしいn件を厳選 (全てが高紛らわしさ、かつローマ字が重複しない)"""
    candidates = []
    seen = set([answer] + list(forbid))
    # プール読みから長さ±1のものだけを候補に (明らかに長さが違うのは除外して難易度UP)
    for r in pool_readings:
        if r in seen:
            continue
        if abs(len(r)-len(answer)) > 1:
            continue
        if not KANA_RE.match(r):
            continue
        candidates.append(r)
    # 合成ひっかけも追加
    for r in synthetic_pool:
        if r in seen or r in candidates:
            continue
        if abs(len(r)-len(answer)) > 1:
            continue
        candidates.append(r)
    # スコアでソート (高紛らわしさ順)
    scored = [( _confusion_score(answer, c), c) for c in candidates]
    scored.sort(key=lambda t: (-t[0], rng.random()))
    # 上位からローマ字重複を避けつつn件
    out = []
    for sc,c in scored:
        if c in seen or c in out:
            continue
        # ローマ字が答えや既存の distractors と重複しないかチェック (Romaji.convertManyと同じロジック)
        test_list = [answer] + out + [c]
        rom = _romaji_many(test_list)
        if len(set(rom)) != len(rom):
            # 重複したらスキップ (同じローマ字に見える選択肢は英語UIで区別できない)
            continue
        # あまりにもスコアが低い(簡単すぎる)のは後回しだが、最終的には採用する
        out.append(c)
        seen.add(c)
        if len(out) >= n:
            break
    # 足りなければ緩い条件でもう一度 (長さ±2、ローマ字重複チェックは維持)
    if len(out) < n:
        extra_cands = []
        for r in pool_readings:
            if r in seen or r==answer or r in out:
                continue
            if abs(len(r)-len(answer))>2:
                continue
            extra_cands.append(r)
        for r in synthetic_pool:
            if r in seen or r in out or r in extra_cands:
                continue
            if abs(len(r)-len(answer))>2:
                continue
            extra_cands.append(r)
        rng.shuffle(extra_cands)
        scored2 = [( _confusion_score(answer, c), c) for c in extra_cands]
        scored2.sort(key=lambda t: (-t[0], rng.random()))
        for sc,c in scored2:
            test_list = [answer] + out + [c]
            rom = _romaji_many(test_list)
            if len(set(rom)) != len(rom):
                continue
            out.append(c)
            seen.add(c)
            if len(out) >= n:
                break
    # それでも足りなければローマ字重複を許容してでも補完 (最終手段)
    if len(out) < n:
        for sc,c in scored:
            if c in out or c in seen:
                continue
            if c not in out:
                out.append(c)
                if len(out) >= n:
                    break
    return out[:n]

def pick_random_readings(reading, pool_readings, forbid, rng, n, length_delta=1):
    # 旧互換: 新ロジックに委譲 (長さフィルタのみ)
    syn = _synthetic_variants(reading, rng)
    return pick_tricky_distractors(reading, pool_readings, forbid, syn, rng, n)


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
            # 合成ひっかけ + 読替スワップを統合して最も紛らわしい3つを厳選
            syn = _synthetic_variants(reading, rng)
            swaps = swap_distractors(word, reading, kj, pool_ans, forbidden, rng)
            for s in swaps:
                if s not in syn:
                    syn.append(s)
            distr = pick_tricky_distractors(reading, pool_ans, forbidden, syn, rng, 3)
            # 最低でも swap が1つ入っていればさらに紛らわしいので、スコア順で入れ直し
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
            syn = _synthetic_variants(answer, rng)
            distr = pick_tricky_distractors(answer, pool_ans, forbidden, syn, rng, 3)
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
                syn = _synthetic_variants(answer, rng)
                distr = pick_tricky_distractors(answer, pool_ans, forbidden, syn, rng, 3)
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
