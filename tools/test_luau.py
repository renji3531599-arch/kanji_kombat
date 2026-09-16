#!/usr/bin/env python3
"""
lupa (LuaJIT) による検証:
  1. 全 .luau ファイルが Lua としてパースできること (構文チェック)
  2. 問題データモジュールを実際に実行し、全問題の構造を検証
"""
import glob
import os
import re
import sys

import lupa
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KANA_RE = re.compile(r'^[\u3041-\u309Fー]+$')


def main():
    print('lupa LuaJIT:', lupa.__version__ if hasattr(lupa, '__version__') else 'ok')
    lua = LuaRuntime(unpack_returned_tuples=True)

    # ---- 1. syntax check every luau file
    files = sorted(
        glob.glob(os.path.join(ROOT, 'src', '**', '*.luau'), recursive=True)
    )
    errors = 0
    for path in files:
        src = open(path, encoding='utf-8').read()
        # Roblox の service 呼び出し等は実行せずパースのみ
        f = lua.eval('function(src, name) local fn, err = load(src, name); return fn ~= nil, err end')
        ok, err = f(src, '@' + os.path.relpath(path, ROOT))
        if not ok:
            print('SYNTAX ERROR:', os.path.relpath(path, ROOT))
            print('   ', err)
            errors += 1
    print('syntax check: %d files, %d errors' % (len(files), errors))
    if errors:
        return 1

    # ---- 2. execute + validate data modules
    data_dir = os.path.join(ROOT, 'src', 'server', 'data')
    total = 0
    for path in sorted(glob.glob(os.path.join(data_dir, '*.luau'))):
        src = open(path, encoding='utf-8').read()
        bank = lua.execute(src)
        assert bank, path
        n = len(bank)
        total += n
        bad = 0
        seen_prompt = set()
        for i in range(1, n + 1):
            q = bank[i]
            assert type(q.p) == str and type(q.a) == str, '%s #%d types' % (path, i)
            assert len(q.d) == 3, '%s #%d distractors=%d' % (path, i, len(q.d))
            ds = [str(q.d[1]), str(q.d[2]), str(q.d[3])]
            assert str(q.a) not in ds, '%s #%d answer in distractors: %s' % (path, i, q.p)
            if len(set(ds)) != 3:
                bad += 1
            if not KANA_RE.match(q.a):
                bad += 1
            for d in ds:
                if not KANA_RE.match(d):
                    bad += 1
            if q.p in seen_prompt:
                bad += 1
            seen_prompt.add(q.p)
        name = os.path.basename(path)
        status = 'OK' if bad == 0 else 'WARN(%d)' % bad
        print('%-28s %5d問  %s' % (name, n, status))
    print('TOTAL: %d questions' % total)
    return 0


if __name__ == '__main__':
    sys.exit(main())
