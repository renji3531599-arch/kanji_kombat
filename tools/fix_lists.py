#!/usr/bin/env python3
"""Apply PDF-extraction fixes to the official level lists (see docs/NOTES-data.md)."""
import os, sys

DATA = os.path.join(os.path.dirname(__file__), '..', 'data', 'official')

def patch(name, pairs, appends=None):
    p = os.path.join(DATA, name + '.txt')
    txt = open(p, encoding='utf-8').read()
    for old, new in pairs:
        assert old in txt, f"{name}: '{old}' not found"
        txt = txt.replace(old, new, 1)
    if appends:
        txt = txt.rstrip('\n') + '\n' + '\n'.join(appends) + '\n'
    open(p, 'w', encoding='utf-8').write(txt)
    print(f"patched {name}")

# K07: bogus glyph 鋟 -> 録 (4年)
patch('K07', [('鋟 未', '録 未')])

# K06: 衠 -> 衛, 贅 -> 賛 (5年)
patch('K06', [('慣 衠', '慣 衛'), ('序 贅', '序 賛')])

# K05: bogus 治(dup) -> 敵, then append remaining 7 grade-6 kanji
patch('K05', [('孝 胸 冶', '孝 胸 敵')], appends=['困 推 株 沿 激 秘 臓 訳'])

# K04a: bogus glyphs 猒 -> 猿, 掔 -> 捗
patch('K04a', [('侵 猒', '侵 猿'), ('恒 掔', '恒 捗')])

# K03a: duplicate 棄 -> 塁 (row 10)
patch('K03a', [('偶 棄 棋', '偶 塁 棋')])

# KP2a: 壤(墊) -> 壌, 涉 -> 渉, 2nd 賜 -> 須, bogus 諹 -> 詮
JOYOU_JYOU = chr(0x58CC)  # 壌
patch('KP2a', [
    ('壤 肖', JOYOU_JYOU + ' 肖'),
    ('紳 涉', '紳 渉'),
    ('津 宵 銃 賜', '津 宵 銃 須'),
    ('核 諹', '核 詮'),
])

# KP2b: bogus 埾 -> 塞; fold 窃 into its row; append 9 reconstructed kanji
patch('KP2b', [
    ('埾 融', '塞 融'),
    ('秩 挿 拙\n窃\n', '秩 挿 拙 窃\n'),
], appends=['錮 稽 窟 膝 臼 畿 餅 顎 頰'])

print('done')
