#!/usr/bin/env python3
"""
KanjiKombat.rbxlx builder — Rojo 無しで開ける Roblox place ファイル (.rbxlx) を生成する。

使い方: python3 tools/build_place.py  ->  KanjiKombat.rbxlx
"""
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
SHARED = os.path.join(SRC, 'shared')
CLIENT_MODULES = os.path.join(SRC, 'client', 'Modules')
OUT = os.path.join(ROOT, 'KanjiKombat.rbxlx')


class Ref:
    counter = 0

    @classmethod
    def next(cls):
        cls.counter += 1
        return 'RBX%d' % cls.counter


def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8') as f:
        return f.read()


def item(cls, name, children='', extra_props=''):
    ref = Ref.next()
    props = '<string name="Name">%s</string>' % escape(name) + extra_props
    return '<Item class="%s" referent="%s"><Properties>%s</Properties>%s</Item>' % (
        cls, ref, props, children)


def script_item(cls, name, source_path):
    source = escape(read(source_path))
    return item(cls, name, extra_props='<ProtectedString name="Source">%s</ProtectedString>' % source)


def folder(name, children):
    return item('Folder', name, children=children)


def build():
    # ----- ReplicatedStorage (src/shared/*.luau を全部 KKShared に入れる)
    shared_files = sorted(f for f in os.listdir(SHARED) if f.endswith('.luau'))
    shared = folder('KKShared', ''.join(
        script_item('ModuleScript', f[:-5], 'src/shared/%s' % f)
        for f in shared_files
    ))
    replicated = item('ReplicatedStorage', 'ReplicatedStorage', children=shared)

    # ----- ServerScriptService
    # src/server/Modules/*.luau を全部入れる。1つでも欠けると Main.server.luau の
    # WaitForChild が永久待機し、ワールドが生成されずキャラクターが落ち続ける。
    module_dir = os.path.join(SRC, 'server', 'Modules')
    module_files = sorted(f for f in os.listdir(module_dir) if f.endswith('.luau'))
    modules = folder('Modules', ''.join(
        script_item('ModuleScript', f[:-5], 'src/server/Modules/%s' % f)
        for f in module_files
    ))
    data_dir = os.path.join(SRC, 'server', 'data')
    data_files = sorted(f for f in os.listdir(data_dir) if f.endswith('.luau'))
    data = folder('Data', ''.join(
        script_item('ModuleScript', f[:-5], 'src/server/data/%s' % f)
        for f in data_files
    ))
    main = script_item('Script', 'KanjiKombat', 'src/server/Main.server.luau')
    # main item with children (main + folders)
    main_with_children = main.replace('</Item>', children_xml([modules, data]) + '</Item>')
    sss = item('ServerScriptService', 'ServerScriptService', children=main_with_children)

    # ----- StarterPlayer
    client_files = sorted(f for f in os.listdir(CLIENT_MODULES) if f.endswith('.luau'))
    client_modules = folder('ClientModules', ''.join(
        script_item('ModuleScript', f[:-5], 'src/client/Modules/%s' % f)
        for f in client_files
    ))
    sps = item('StarterPlayerScripts', 'StarterPlayerScripts', children=(
        script_item('LocalScript', 'KanjiKombatClient', 'src/client/KanjiKombatClient.client.luau') + client_modules
    ))
    starter = item('StarterPlayer', 'StarterPlayer', children=sps)

    # ----- Workspace
    # サーバースクリプトの起動より先にキャラクターが湧く場合、およびスクリプトが
    # モジュール欠落で止まった場合に備えて、床と SpawnLocation を place 側に置く。
    floor = item('Part', 'Baseplate', extra_props=(
        '<bool name="Anchored">true</bool>'
        '<bool name="Locked">true</bool>'
        '<CoordinateFrame name="CFrame">'
        '<X>0</X><Y>-2</Y><Z>0</Z>'
        '<R00>1</R00><R01>0</R01><R02>0</R02>'
        '<R10>0</R10><R11>1</R11><R12>0</R12>'
        '<R20>0</R20><R21>0</R21><R22>1</R22>'
        '</CoordinateFrame>'
        '<Vector3 name="size"><X>512</X><Y>4</Y><Z>512</Z></Vector3>'
        '<Color3uint8 name="Color3uint8">1842204</Color3uint8>'
        '<token name="TopSurface">0</token>'
        '<token name="BottomSurface">0</token>'
    ))
    spawn_pad = item('SpawnLocation', 'Spawn', extra_props=(
        '<bool name="Anchored">true</bool>'
        '<CoordinateFrame name="CFrame">'
        '<X>0</X><Y>1.5</Y><Z>54</Z>'
        '<R00>1</R00><R01>0</R01><R02>0</R02>'
        '<R10>0</R10><R11>1</R11><R12>0</R12>'
        '<R20>0</R20><R21>0</R21><R22>1</R22>'
        '</CoordinateFrame>'
        '<Vector3 name="size"><X>12</X><Y>1</Y><Z>12</Z></Vector3>'
        '<Color3uint8 name="Color3uint8">5918550</Color3uint8>'
        '<token name="TopSurface">0</token>'
        '<token name="BottomSurface">0</token>'
        '<bool name="Neutral">true</bool>'
        '<float name="Duration">0</float>'
    ))
    workspace = item('Workspace', 'Workspace', children=floor + spawn_pad)

    header = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
              'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
              'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
    xml = header + workspace + replicated + sss + starter + '</roblox>'
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n')
        f.write(xml)
    print('wrote', OUT, '%.1f KB' % (os.path.getsize(OUT) / 1024))


def children_xml(items):
    return ''.join(items)


if __name__ == '__main__':
    sys.exit(build())
