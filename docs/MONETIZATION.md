# ショップ / Monetization setup

Kanji Kombat の課金は、競技の正解を買わせず、コスメとゲーム内進行だけを扱います。
Robux 商品の ID はリポジトリに実在値をハードコードしていません。公開する Roblox experience の Creator Dashboard で作成した ID を設定してください。

## 1. 商品を作成する

`GameConfig.luau` の `SHOP_ITEMS` と同じ商品を Creator Dashboard に作成します。

| key | kind | 既定の内容 |
| --- | --- | --- |
| `coin_spark` | Developer Product | 500 coins |
| `coin_burst` | Developer Product | 2,400 coins |
| `vip_dojo` | Game Pass | VIP dojo title / aura |
| `neon_title` | Game Pass | cosmetic title |
| `practice_pack` | Developer Product | 850 coins + 250 XP |

作成した数値 ID を各 item の `id` に入力します。テスト・Studioでは `0` のままでも正常に遊べます。

## 2. 付与の流れ

- Developer Product: `PurchaseService` が `MarketplaceService.ProcessReceipt` で ID を照合し、`StatsService` 経由で付与します。
- Game Pass: `UserOwnsGamePassAsync` と `PromptGamePassPurchaseFinished` の両方で所有状態を同期します。
- `PurchaseId` はプロフィールに最大30件保存し、同じレシートの二重付与を防ぎます。
- プロフィールがまだロードされていない場合は `NotProcessedYet` を返し、Roblox が後で再試行できるようにします。
- クライアントから送られた coins / XP / item の数値は一切信用しません。

## 3. 競技の公平性

購入できるものは、コスメ、コイン、XP、練習用の進行だけです。Elo、正解表示、回答時間の延長、ダメージ倍率、対戦中のスキルエネルギーは購入では得られません。`StatsService` と `MatchService` がサーバー側で勝敗と報酬を決定します。

## 4. 公開前チェック

1. Experience Settings の Security で必要な API access を設定する。
2. 本番 ID を `GameConfig.SHOP_ITEMS` に入れる。
3. Test Server で Developer Product の receipt と Game Pass 所有済み再参加を確認する。
4. `python3 tools/test_luau.py` を実行する。
5. Roblox の Monetization / Community Standards と、対象地域の法令・年齢表示に従って価格・説明を確認する。
