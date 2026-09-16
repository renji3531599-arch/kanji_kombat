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


# ---------------------------------------------------------------- distractors
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


def pick_random_readings(reading, pool_readings, forbid, rng, n, length_delta=1):
    L = len(reading)
    cands = [r for r in pool_readings
             if abs(len(r) - L) <= length_delta and r != reading and r not in forbid]
    rng.shuffle(cands)
    return cands[:n]


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
            distr = swap_distractors(word, reading, kj, pool_ans, forbidden, rng)
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
            distr = pick_random_readings(answer, pool_ans, forbidden, rng, 3)
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
                distr = pick_random_readings(answer, pool_ans, forbidden, rng, 3)
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
