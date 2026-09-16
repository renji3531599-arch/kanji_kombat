# 漢字コンバット / KANJI KOMBAT 🈶⚔️

Roblox で遊べる**漢字読みオンリーのオンライン対戦ゲーム**。
出題難易度は**日本漢字能力検定（漢検）の級別漢字表（2020年改正）に準拠**し、
**10級〜1級の全12級 × 各1,000問 = 計12,000問**を内蔵しています。

![levels](https://img.shields.io/badge/%E6%BC%A2%E6%A4%9C-10%E7%B4%9A%E2%88%921%E7%B4%9A-red) ![questions](https://img.shields.io/badge/%E5%95%8F%E9%A1%8C-12,000%E5%95%8F-blue)

---

## English

**Kanji Kombat** is an online kanji *reading* battle game for Roblox. Pick a level, get matched with another player, and answer 4-choice reading questions; correct answers deal damage, and each level has its own Elo rating.

* **12,000 questions** — 12 levels × 1,000, following the Japan Kanji Aptitude Test (*Kanken*) grades 10 → 1. Grade 10 is 1st-year elementary (80 kanji); grade 1 is expert level (~6,000 kanji).
* **Bilingual UI** — Japanese for players whose Roblox locale is `ja*`, English for everyone else, with a **🌐 toggle** in the lobby (your choice is saved).
* **Made for learners** — in English mode the choices show **romaji + kana** (e.g. `kyoushuu / きょうしゅう`), and each level is labelled with its school grade and a rough **JLPT equivalent** (`Level 10 · Grade 1 (elementary) · ≈ JLPT N5`).
* **Match rules** — 10 rounds, 12 seconds per question, 100 HP, base damage 20 (+10 for a fast answer, +5 for answering first); sudden death if HP is tied; Elo rating per level (starts at 1000).

Run it: open `KanjiKombat.rbxlx` in Roblox Studio and press ▶ Play (publish the place and raise the max player count for online matches).

---

## 多言語対応（日本語 / English）

英語圏向けに、UI は **日本語 / 英語の自動切り替え + 手動切り替え**に対応しています。

| 項目 | 日本語UI | 英語UI |
| --- | --- | --- |
| タイトル | 漢字コンバット | **KANJI KOMBAT**（起動時のタイトル画面は英語メイン） |
| レベルの呼び方 | 10級 / 準2級 | `Level 10` / `Level Pre-2` |
| レベルの説明 | 小学校1年生修了程度 | `Grade 1 (elementary) · ≈ JLPT N5` |
| 読みの選択肢 | ひらがな（きょうしゅう） | **ローマ字 + かな**（`kyoushuu` / きょうしゅう） |
| 答えた後 | 正解は「きょうしゅう」 | `Wrong… the answer is “kyoushuu / きょうしゅう”` |
| リーダーボード | 勝数 | `Wins` |

* 言語は **端末のロケール（`Player.LocaleId`）から自動判定**します。`ja*` なら日本語、それ以外は英語。
* ロビー右上の **🌐 ボタン**でいつでも切り替え可能。選んだ言語は DataStore に保存され、次回以降も使われます。
* サーバーは文章ではなく「キー + パラメータ」を送るため、同じサーバーに日本語・英語のプレイヤーが混在しても正しく表示されます。
* 文言の追加方法・翻訳の足し方は [docs/I18N.md](docs/I18N.md) を参照。

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
  shared/I18n.luau              # 日本語/英語の文言とロケール解決 (t/levelTitle/levelDesc)
  shared/Romaji.luau            # かな → ローマ字 (英語UIで読みを併記するため)
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
  test_luau.py                  # 構文チェック + i18n/ローマ字検証 + 問題データ検証 (lupa/LuaJIT)
  client_sim.lua                # Roblox API のモック (クライアントのスモークテスト用)
  client_test_hook.luau         # そのモックからUIの表示文字列を検査するための覗き窓
  server_sim.lua                # サーバーをモック上で起動し、C2S→S2C を通すスモークテスト
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

### 多言語まわりの検証

```bash
python3 tools/test_luau.py            # lupa が必要 (pip install lupa)
# - 全ファイルの構文チェック
# - Romaji: かな→ローマ字のケース + 12,000問すべてで選択肢4つのローマ字が重複しないこと
# - I18n: ja/en の全キーが揃っていること・コードから参照されたキーが存在すること
# - 問題データ: 選択肢4つ・読みはひらがな・誤答重複なし
# - クライアント: Roblox API をモックして起動→対戦→練習→🌐言語切替を通し、
#   実際にUIへ表示された文字列 (Level 10 / juumoku / きょうしゅう など) を検証
# - サーバー: Main.server.luau をモック上で起動し、クライアント役として C2S
#   (practiceStart / practiceSubmit / queue / submit) を発火 →
#   practiceQ・question・answerResult・matchEnd が実際に返ってくることを検証
#   (リモートの繋ぎ忘れで「練習で問題が1問も出ない」状態になるのを検出する)
```

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
