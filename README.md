# 漢字コンバット (Kanji Kombat) 🈶⚔️

Roblox で遊べる**漢字読みオンリーのオンライン対戦ゲーム**。
出題難易度は**日本漢字能力検定（漢検）の級別漢字表（2020年改正）に準拠**し、
**10級〜1級の全12級 × 各1,000問 = 計12,000問**を内蔵しています。

![levels](https://img.shields.io/badge/%E6%BC%A2%E6%A4%9C-10%E7%B4%9A%E2%88%921%E7%B4%9A-red) ![questions](https://img.shields.io/badge/%E5%95%8F%E9%A1%8C-12,000%E5%95%8F-blue)

---

## 遊び方

| モード | 内容 |
| --- | --- |
| **対戦** | 同じ級を選んだプレイヤーと即マッチング。10問勝負・先に相手のHPをゼロにした方が勝ち |
| **練習** | 1人でひたすら読みトレーニング。連続正解数を競う |

### 対戦ルール
- 1問 12秒の**4択読み問題**（言葉／単漢字の読み方を選ぶ）
- 正答で相手にダメージ: 基本 **20** ＋ **3秒以内の速答 +10** ＋ **一番乗り +5**
- 誤答・タイムオーバーはダメージなし
- 10問終了時にHPが同点なら**サドンデス**
- 勝敗で級ごとの **Eloレーティング**（初期値1000）が変動。ロビーUIに各級のレートを表示

## セットアップ

### 方法A: placeファイルをそのまま開く（一番簡単）
1. `KanjiKombat.rbxlx` を Roblox Studio で開く（ダブルクリック）
2. ▶ Play で一人用動作確認（練習モード、または対戦は1人だと待機のまま）
3. オンライン対戦させるには:
   - **ファイル → ゲームをRobloxに公開** で公開する
   - ゲーム設定で **最大プレイヤー数を2以上** にする
   - 永続化（レート保存）したい場合は **ゲーム設定 → セキュリティ → StudioからのAPIアクセスを有効化** もオンにする

### 方法B: Rojo で開発
```bash
rojo serve default.project.json   # Studio の Rojo プラグインと接続
# または
rojo build default.project.json -o KanjiKombat.rbxlx
```

## 構成

```
src/
  shared/GameConfig.luau        # 級定義・ダメージ値などの共有設定
  server/
    Main.server.luau            # エントリポイント (リモート生成・ワールド構築・ループ)
    Modules/
      QuestionBank.luau         # 12レベルの問題バンク
      MatchService.luau         # マッチメイキング・対戦進行・練習モード
      StatsService.luau         # DataStore保存・Eloレーティング・リーダーボード
      ArenaService.luau         # 級ごとの対戦アリーナ生成
      LobbyService.luau         # ロビーマップ生成
    data/
      Questions_K10..K01.luau   # 生成された問題データ (各1000問)
  client/
    KanjiKombatClient.client.luau
    Modules/UiKit.luau
data/official/*.txt             # 公式 級別漢字表 (2020改正) の配当漢字リスト
tools/
  validate_lists.py             # 級リストの検証 (字数・漢検累計との整合)
  fix_lists.py                  # PDF抽出由来の文字修正の適用記録
  generate_questions.py         # 問題ジェネレーター
  test_luau.py                  # 構文チェック + 問題データ検証 (lupa/LuaJIT)
  build_place.py                # .rbxlx 生成
```

## 問題データについて

- **級の漢字セット**は漢字能力検定協会が公表する**級別漢字表（2020年2月発表の新配当漢字）**に準拠。
  10級=80字 → 5級=1026字（学習漢字と完全一致）→ 4級=1339字 → 3級=1623字 → 準2級=1951字 → 2級=2136字（常用漢字と完全一致）。
  ※ 2020年改正後の公式値では**4級は累計1339字**です（一部サイトで見られる「942字」は旧基準・誤記と思われます）。
- **準1級**（約3000字）＝常用漢字＋JIS第1水準の非常用漢字、**1級**（約6000字）＝さらにJIS第2水準を追加（公式リストの近似）。
- 問題は **KANJIDIC2**（漢字の音訓読み）と **JMdict**（語彙と読み）から自動生成し、
  誤答選択肢（ダミー）は「同じ漢字の別の音読みへの読み替え」（例: 残念→ざんねん vs さんねん）など、
  漢検で実際に引っかけになる読みを優先的に採用しています。
- 各級とも**その級の新出漢字を必ず1問以上カバー**（10級〜5級は単漢字の読み問題も含む）。

データを再生成する場合:

```bash
pip install jamdict jamdict-data lupa
python3 tools/generate_questions.py   # src/server/data/ に再出力
python3 tools/test_luau.py            # 検証
python3 tools/build_place.py          # .rbxlx 再生成
```

## クレジット・ライセンス

- 問題生成に使用した辞書データ:
  - **KANJIDIC2 / JMdict** — Copyright (C) EDRDG (Jim Breen 等編集)
    [Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/) で許諾。
    (`jamdict-data` パッケージ経由で利用)
- 級別の漢字セットは **日本漢字能力検定協会「級別漢字表」（2020年2月発表）** を参照。
  本プロジェクトは同協会および漢字能力検定と**無関係な非公式ファンプロジェクト**です。
- ゲームコード: リポジトリのライセンスに従う。
