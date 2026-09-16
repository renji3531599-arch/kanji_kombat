#!/usr/bin/env python3
"""Validate the transcribed official kanji level lists against KANJIDIC2."""
import sqlite3, sys, os, re

DB = '/usr/local/lib/python3.11/dist-packages/jamdict_data/jamdict.db'
DATA = os.path.join(os.path.dirname(__file__), '..', 'data', 'official')

# expected new-kanji counts per level file
EXPECTED = {
    'K10': 80, 'K09': 160, 'K08': 200, 'K07': 202, 'K06': 193, 'K05': 191,
    'K04a': 160, 'K04b': 153, 'K03a': 160, 'K03b': 124,
    'KP2a': 160, 'KP2b': 168,
}

def load(name):
    p = os.path.join(DATA, name + '.txt')
    txt = open(p, encoding='utf-8').read()
    # keep only CJK ideographs (plus ー-safety)
    chars = re.findall(r'[\u3400-\u9FFF\U00020000-\U0002A6DF]', txt)
    return chars

def main():
    db = sqlite3.connect(DB)
    cur = db.cursor()
    valid = set(r[0] for r in cur.execute("SELECT literal FROM character"))
    grades = {}
    for lit, g in cur.execute("SELECT literal, grade FROM character WHERE grade IS NOT NULL"):
        grades.setdefault(int(g), set()).add(lit)
    kyoiku = set().union(*(grades.get(i, set()) for i in range(1, 7)))
    jouyou = set().union(*(grades.get(i, set()) for i in list(range(1, 9))))
    print(f"kanjidic2: kyoiku={len(kyoiku)} jouyou={len(jouyou)} total_chars={len(valid)}")

    levels = {}
    ok = True
    for name, exp in EXPECTED.items():
        chars = load(name)
        levels[name] = chars
        dups = [c for c in set(chars) if chars.count(c) > 1]
        unknown = [c for c in chars if c not in valid]
        status = []
        if len(chars) != exp:
            status.append(f"COUNT {len(chars)} != {exp}")
            ok = False
        if dups:
            status.append(f"DUP {dups}")
            ok = False
        if unknown:
            status.append(f"NOT-IN-KANJIDIC2 {unknown}")
        print(f"{name}: {len(chars)} chars (expect {exp}) {'; '.join(status)}")

    # cumulative structure
    order = ['K10','K09','K08','K07','K06','K05','K04a','K04b','K03a','K03b','KP2a','KP2b']
    cum = set()
    prev = 0
    print('--- cumulative ---')
    for name in order:
        newset = set(levels[name])
        cum |= newset
        print(f"{name}: +{len(newset)} -> cum {len(cum)}")
    # kyoiku alignment: cum(K10..K05) should equal kyoiku exactly
    cum5 = set()
    for name in ['K10','K09','K08','K07','K06','K05']:
        cum5 |= set(levels[name])
    extra = cum5 - kyoiku
    missing = kyoiku - cum5
    print(f"cum(10-5級)={len(cum5)} vs kyoiku={len(kyoiku)}")
    if extra: print("  EXTRA (in lists, not kyoiku):", ''.join(sorted(extra)))
    if missing: print("  MISSING (kyoiku, not in lists):", ''.join(sorted(missing)))

    cum8 = cum  # through 準2級
    in_jouyou = cum8 & jouyou
    non_jouyou = cum8 - jouyou
    print(f"cum(〜準2級)={len(cum8)}: jouyou-内={len(in_jouyou)} 表外={len(non_jouyou)}: {''.join(sorted(non_jouyou))}")
    missing_jouyou = jouyou - cum8
    print(f"  jouyou残り(=2級新出のはず185字): {len(missing_jouyou)}: {''.join(sorted(missing_jouyou))}")

    # within-level kyoiku bounds sanity
    for name, lo, hi in [('K10',1,1),('K09',2,2),('K08',3,3),('K07',4,4),('K06',5,5),('K05',6,6)]:
        pass
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
