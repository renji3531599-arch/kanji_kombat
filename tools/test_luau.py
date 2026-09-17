#!/usr/bin/env python3
"""
lupa (LuaJIT) による検証:
  1. 全 .luau ファイルが Lua としてパースできること (構文チェック)
  2. KKShared (GameConfig / Romaji / I18n) の単体テスト
  3. クライアントを Roblox API のモック上で起動し、UIに出た文字列を検証
  4. サーバー (Main.server.luau) をモック上で起動し、C2S を発火して応答を検証
     → 「練習で問題が出ない / 対戦がマッチしない」のような配線ミスを検出する
  5. 問題データモジュールを実際に実行し、全問題の構造を検証
  6. 全12,000問で選択肢4つのローマ字が重複しないこと (英語UI用の確認)
  7. I18n のキーがコードから参照されている / 参照キーが存在する
"""
import glob
import os
import re
import sys

import lupa
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KANA_RE = re.compile(r'^[\u3041-\u309Fー]+$')

# Roblox の require / script / game をスタブして KKShared モジュールを読み込む
STUB = """
__mods = {}
script = { Parent = { WaitForChild = function(_, name) return __mods[name] end } }
function require(mod) return mod end
function __load(name, src)
    local fn = assert(load(src, '@' .. name))
    local mod = fn()
    if mod ~= nil then __mods[name] = mod end
    return mod
end
function __romaji_check()
    local total, collisions = 0, 0
    local samples = {}
    for name, bank in pairs(__mods) do
        if type(name) == 'string' and name:sub(1, 10) == 'Questions_' and type(bank) == 'table' then
            for i = 1, #bank do
                local q = bank[i]
                local r = __mods.Romaji.convertMany({ q.a, q.d[1], q.d[2], q.d[3] })
                total = total + 1
                local seen, dup = {}, false
                for j = 1, 4 do
                    if seen[r[j]] then dup = true end
                    seen[r[j]] = true
                end
                if dup then
                    collisions = collisions + 1
                    if #samples < 5 then
                        samples[#samples + 1] = q.p .. ' [' .. table.concat(r, ' / ') .. ']'
                    end
                end
            end
        end
    end
    return total, collisions, table.concat(samples, ' ; ')
end
function __convert_many_ok(list)
    local r = __mods.Romaji.convertMany(list)
    if #r ~= #list then return false, table.concat(r, ',') end
    local seen = {}
    for i = 1, #r do
        if seen[r[i]] then return false, table.concat(r, ' / ') end
        seen[r[i]] = true
    end
    return true, table.concat(r, ' / ')
end
function __lua_keys()
    local out = {}
    for _, k in ipairs(__mods.I18n.keys()) do
        out[#out + 1] = k
    end
    table.sort(out)
    return table.concat(out, '\\n')
end
"""

ROMAJI_CASES = [
    ('じゅうもく', 'juumoku'),
    ('じゅっもく', 'jummoku'),
    ('がっこう', 'gakkou'),
    ('まっちゃ', 'matcha'),
    ('きょうしゅう', 'kyoushuu'),
    ('とうきょう', 'toukyou'),
    ('らーめん', 'raamen'),
    ('しんよう', "shin'you"),
    ('こんいん', "kon'in"),
    ('ん', 'n'),
    ('じろう', 'jirou'),
    ('ぢろう', 'jirou'),
]

CLIENT_HANDLERS = [
    # クライアント内のコールバック (行番号で特定する)
    ('s2c', 'S2C.OnClientEvent:Connect(function(data)'),
    ('toggle', 'langButton.MouseButton1Click:Connect(function()'),
    ('level', 'btn.MouseButton1Click:Connect(function()'),
    ('battle', 'battleButton.MouseButton1Click:Connect(function()'),
    ('practice', 'practiceButton.MouseButton1Click:Connect(function()'),
    ('cancel', 'cancelButton.MouseButton1Click:Connect(function()'),
    ('exit', 'pracExit.MouseButton1Click:Connect(function()'),
    ('result', 'resultOk.MouseButton1Click:Connect(function()'),
    ('choice', 'choice.button.MouseButton1Click:Connect(function()'),
]

I18N_CHECKS = [
    ('ja', 'title', '漢字コンバット'),
    ('en', 'title', 'KANJI KOMBAT'),
    ('ja', 'battleButton', '対戦エントリー'),
    ('en', 'battleButton', 'Find a Match'),
    ('ja', 'suddenDeath', 'サドンデス！'),
    ('en', 'suddenDeath', 'SUDDEN DEATH!'),
]


def lua_table_to_list(lua, tbl):
    """Lua の配列テーブルを Python list にする (I18n.keys() 用)"""
    return lua.eval('function(t) local out = {} for i = 1, #t do out[i] = t[i] end return table.concat(out, "\\n") end')(tbl).split('\n')


def load_shared(lua):
    """KKShared のモジュール群を Roblox 風スタブで読み込む"""
    lua.execute(STUB)
    load = lua.globals()['__load']
    for name in ('GameConfig', 'Romaji', 'I18n'):
        path = os.path.join(ROOT, 'src', 'shared', name + '.luau')
        load(name, open(path, encoding='utf-8').read())
    return lua.globals()['__mods']


def client_sim(lua):
    """Roblox API をモックしてクライアントを実行するスモークテスト"""
    print()
    print('--- client smoke test (mock Roblox API) ---')
    client_path = os.path.join(ROOT, 'src', 'client', 'KanjiKombatClient.client.luau')
    client_src = open(client_path, encoding='utf-8').read()
    # UIに実際に表示された文字列を検証するためのテストフック (実機のソースは変更しない)
    client_src += '\n' + open(os.path.join(ROOT, 'tools', 'client_test_hook.luau'), encoding='utf-8').read()
    lua.globals()['__load']('UiKit', open(os.path.join(
        ROOT, 'src', 'client', 'Modules', 'UiKit.luau'), encoding='utf-8').read())

    sim = lua.execute(open(os.path.join(ROOT, 'tools', 'client_sim.lua'), encoding='utf-8').read())
    line_of = []
    for key, needle in CLIENT_HANDLERS:
        if needle not in client_src:
            print('  FAIL callback not found: %s (%s)' % (key, needle))
            return 1
        line_of.append(client_src[:client_src.index(needle)].count('\n') + 1)

    summary, errs = sim.run_all(client_src, *line_of)
    for line in summary.split('\n'):
        print('  ' + line)
    if errs:
        for line in errs.split('\n'):
            print('  FAIL', line)
        return 1
    return 0


SERVER_MODULES = [
    # QuestionBank は読み込み時に Data/Questions_* を require するので、この順序で
    'QuestionBank', 'StatsService', 'ArenaService', 'LobbyService',
    'CurrencyService', 'ProgressionService', 'ShopService', 'MatchService',
]


def server_sim(lua, mods):
    """Main.server.luau を実際に起動し、C2S を発火して応答を検証するスモークテスト"""
    print()
    print('--- server smoke test (mock Roblox API) ---')
    # QuestionBank が WaitForChild("Questions_*") できるように問題データを先に登録しておく
    for path in sorted(glob.glob(os.path.join(ROOT, 'src', 'server', 'data', '*.luau'))):
        name = os.path.basename(path)[:-5]
        mods[name] = lua.globals()['__load'](
            name, open(path, encoding='utf-8').read())

    sim = lua.execute(open(os.path.join(ROOT, 'tools', 'server_sim.lua'), encoding='utf-8').read())
    module_dir = os.path.join(ROOT, 'src', 'server', 'Modules')
    for name in SERVER_MODULES:
        sim.add(name, open(os.path.join(module_dir, name + '.luau'), encoding='utf-8').read())
    sim.add('KanjiKombat', open(os.path.join(ROOT, 'src', 'server', 'Main.server.luau'),
                                encoding='utf-8').read())

    summary, errs = sim.run()
    print('  ' + summary)
    if errs:
        for line in errs.split('\n'):
            print('  FAIL', line)
        return 1
    return 0


def source_keys():
    """src/ から I18n のキー参照を集める (英語UIの文言が定義されているか確認するため)"""
    used = set()
    for path in glob.glob(os.path.join(ROOT, 'src', '**', '*.luau'), recursive=True):
        src = open(path, encoding='utf-8').read()
        for args in re.findall(r'I18n\.t\(([^\n]*)', src):
            # == "manual" のような比較リテラルを除外してからキー抽出 (旧バグ: [^\\n] は \\ と n を除外)
            cleaned = re.sub(r'[=~]=\s*"[A-Za-z][A-Za-z0-9_]*"', '', args)
            for key in re.findall(r'"([A-Za-z][A-Za-z0-9_]*)"', cleaned):
                used.add(key)
        for key in re.findall(r'send\([^\n]*key\s*=\s*"([A-Za-z][A-Za-z0-9_]*)"', src):
            used.add(key)
    return used






def module_tests(lua, mods):
    """Romaji / I18n の単体テストとキー整合チェック"""
    print()
    print('--- shared modules (Romaji / I18n) ---')
    errors = 0
    Romaji, I18n = mods['Romaji'], mods['I18n']

    for kana, want in ROMAJI_CASES:
        got = Romaji.convert(kana)
        if got != want:
            print('  FAIL romaji %s -> %s (want %s)' % (kana, got, want))
            errors += 1
    ok, detail = lua.execute("return __convert_many_ok({'じろう','ぢろう','かかん','きたん'})")
    if not ok:
        print('  FAIL convertMany not distinct:', detail)
        errors += 1
    print('  romaji: %d cases + convertMany OK' % len(ROMAJI_CASES))

    for locale, key, want in I18N_CHECKS:
        I18n.setLocale(locale)
        got = I18n.t(key)
        if got != want:
            print('  FAIL i18n[%s].%s = %r (want %r)' % (locale, key, got, want))
            errors += 1

    I18n.setLocale('ja')
    if I18n.levelTitle('K10') != '10級':
        print('  FAIL levelTitle(K10) ja =', I18n.levelTitle('K10'))
        errors += 1
    I18n.setLocale('en')
    if I18n.levelTitle('K10') != 'Level 10':
        print('  FAIL levelTitle(K10) en =', I18n.levelTitle('K10'))
        errors += 1
    if 'JLPT N5' not in I18n.levelDesc('K10'):
        print('  FAIL levelDesc(K10) en should mention JLPT:', I18n.levelDesc('K10'))
        errors += 1
    if I18n.t('profileStats', {'wins': 3, 'losses': 1, 'streak': 2}).find('3W') < 0:
        print('  FAIL interpolation en')
        errors += 1
    I18n.setLocale('ja')
    if I18n.t('profileStats', {'wins': 3, 'losses': 1, 'streak': 2}).find('3勝') < 0:
        print('  FAIL interpolation ja')
        errors += 1
    for loc, want in (('ja-jp', 'ja'), ('en-us', 'en'), ('de-de', 'en'), ('', 'en')):
        if I18n.localeFromId(loc) != want:
            print('  FAIL localeFromId(%r) = %s (want %s)' % (loc, I18n.localeFromId(loc), want))
            errors += 1

    # 全キーに ja / en の両方が入っているか
    keys = lua.execute('return __lua_keys()').split('\n')
    for key in keys:
        for locale in ('ja', 'en'):
            text = I18n.raw(key, locale)
            if text is None or text == '':
                print('  FAIL missing %s translation: %s' % (locale, key))
                errors += 1
    if errors == 0:
        print('  i18n: %d keys x (ja, en) OK' % len(keys))

    used = source_keys()
    missing = sorted(k for k in used if k not in keys)
    unused = sorted(k for k in keys if k not in used)
    if missing:
        print('  FAIL keys referenced in code but not defined:', ', '.join(missing))
        errors += 1
    if unused:
        print('  WARN strings defined but never used:', ', '.join(unused))
    if not missing and not unused:
        print('  i18n keys: all used, none missing')
    return errors


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

    # ---- 2. shared modules
    mods = load_shared(lua)
    errors += module_tests(lua, mods)

    # ---- 3. client smoke test (mock Roblox API)
    errors += client_sim(lua)

    # ---- 3b. server smoke test (mock Roblox API)
    errors += server_sim(lua, mods)

    # ---- 4. execute + validate data modules
    print()
    print('--- question data ---')
    data_dir = os.path.join(ROOT, 'src', 'server', 'data')
    total = 0
    for path in sorted(glob.glob(os.path.join(data_dir, '*.luau'))):
        src = open(path, encoding='utf-8').read()
        bank = lua.execute(src)
        assert bank, path
        mods[os.path.basename(path)[:-5]] = bank  # 4. のローマ字チェックで使う
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

    # ---- 5. ローマ字の重複チェック (英語UIで選択肢が区別できるか)
    print()
    print('--- english mode (romaji choices) ---')
    n_total, collisions, samples = lua.execute('return __romaji_check()')
    print('romaji check: %d questions, %d with duplicate romaji' % (n_total, collisions))
    if samples:
        print('  e.g.', samples)
    if collisions:
        errors += 1

    # ---- 6. 誤答が機械的連濁捏造になっていないこと (いちにち→いぢにち 禁止)
    print()
    print('--- distractor quality ---')
    k10 = mods['Questions_K10']
    if k10 is not None:
        found_ichinichi = None
        found_gakkou = None
        n = len(k10)
        fake_rendaku = 0
        for i in range(1, n + 1):
            q = k10[i]
            ds = [str(q.d[1]), str(q.d[2]), str(q.d[3])]
            if q.p == '一日':
                found_ichinichi = (q.a, ds)
            if q.p == '学校':
                found_gakkou = (q.a, ds)
        if found_ichinichi:
            a, ds = found_ichinichi
            print('  一日 -> %s  (%s)' % (a, ' / '.join(ds)))
            if 'いぢにち' in ds:
                print('  FAIL 一日 has mechanical rendaku distractor いぢにち')
                errors += 1
        else:
            print('  WARN no 一日 question in K10')
        if found_gakkou:
            a, ds = found_gakkou
            print('  学校 -> %s  (%s)' % (a, ' / '.join(ds)))
            if a == 'がっこう' and 'がっきょう' not in ds:
                # 音訓が少ない校は きょう への入れ替えが現実的なミス。プール埋めでもよいが
                # ミス候補があるなら採用されているはず。
                print('  WARN 学校 missing がっきょう (may be rng if other misses filled the 3)')
        else:
            print('  WARN no 学校 question in K10')
    else:
        print('  FAIL Questions_K10 not loaded')
        errors += 1

    # ---- 7. place (rbxlx) 整合性: モジュール欠落でワールド未生成→落下、の回帰防止
    place = os.path.join(ROOT, 'KanjiKombat.rbxlx')
    if os.path.exists(place):
        print()
        print('--- place file (KanjiKombat.rbxlx) ---')
        xml = open(place, encoding='utf-8').read()
        place_errors = 0
        for path in sorted(glob.glob(os.path.join(ROOT, 'src', 'server', 'Modules', '*.luau'))):
            name = os.path.basename(path)[:-5]
            if '<string name="Name">%s</string>' % name not in xml:
                print('  FAIL module missing from place:', name)
                place_errors += 1
        for path in sorted(glob.glob(os.path.join(ROOT, 'src', 'server', 'data', '*.luau'))):
            name = os.path.basename(path)[:-5]
            if '<string name="Name">%s</string>' % name not in xml:
                print('  FAIL question data missing from place:', name)
                place_errors += 1
        if '<Item class="SpawnLocation"' not in xml:
            print('  FAIL no SpawnLocation in place (players fall forever before scripts run)')
            place_errors += 1
        if place_errors == 0:
            print('  all server modules, question data and SpawnLocation embedded: OK')
        errors += place_errors

    print()
    print('RESULT:', 'OK' if errors == 0 else 'NG (%d)' % errors)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
