--!nocheck
-- 漢字コンバット shared configuration (ReplicatedStorage.KKShared.GameConfig)
-- 超拡張版: 対戦システム・課金・エコノミー・バトルパス・ランクを完全統合

local GameConfig = {}

GameConfig.GAME_NAME = "漢字コンバット"
GameConfig.GAME_NAME_EN = "KANJI KOMBAT" -- 英語UI用のタイトル (ロゴ表記)
GameConfig.LOCALES = { "ja", "en" }       -- 対応ロケール (切り替え順)
GameConfig.DEFAULT_LOCALE = "en"          -- 日本語以外のロケールは英語UIにフォールバック

-- レベル定義。label/desc は日本語UI、en = { label, desc } は英語UI用、
-- jlpt は英語UI向けの「JLPT の目安」(あくまで目安。漢検の級とは別制度)。
GameConfig.LEVELS = {
	{ key = "K10", label = "10級",  desc = "小学校1年生修了程度", kanji = 80,   color = { 90, 185, 105 },
		en = { label = "Level 10", desc = "Grade 1 (elementary)" }, jlpt = "≈ JLPT N5", tier = "Bamboo" },
	{ key = "K09", label = "9級",   desc = "小学校2年生修了程度", kanji = 240,  color = { 110, 175, 70 },
		en = { label = "Level 9", desc = "Grade 2 (elementary)" }, jlpt = "≈ JLPT N5", tier = "Bamboo" },
	{ key = "K08", label = "8級",   desc = "小学校3年生修了程度", kanji = 440,  color = { 150, 165, 50 },
		en = { label = "Level 8", desc = "Grade 3 (elementary)" }, jlpt = "≈ JLPT N4", tier = "Bamboo" },
	{ key = "K07", label = "7級",   desc = "小学校4年生修了程度", kanji = 642,  color = { 190, 155, 40 },
		en = { label = "Level 7", desc = "Grade 4 (elementary)" }, jlpt = "≈ JLPT N3", tier = "Bronze" },
	{ key = "K06", label = "6級",   desc = "小学校5年生修了程度", kanji = 835,  color = { 215, 130, 35 },
		en = { label = "Level 6", desc = "Grade 5 (elementary)" }, jlpt = "≈ JLPT N3", tier = "Bronze" },
	{ key = "K05", label = "5級",   desc = "小学校6年生修了程度", kanji = 1026, color = { 235, 100, 30 },
		en = { label = "Level 5", desc = "Grade 6 (elementary)" }, jlpt = "≈ JLPT N2", tier = "Silver" },
	{ key = "K04", label = "4級",   desc = "中学校在学程度",      kanji = 1339, color = { 240, 70, 45 },
		en = { label = "Level 4", desc = "Junior high (in progress)" }, jlpt = "≈ JLPT N2", tier = "Silver" },
	{ key = "K03", label = "3級",   desc = "中学校卒業程度",      kanji = 1623, color = { 235, 50, 75 },
		en = { label = "Level 3", desc = "Junior high graduate" }, jlpt = "≈ JLPT N1", tier = "Gold" },
	{ key = "KP2", label = "準2級", desc = "高校在学程度",        kanji = 1951, color = { 220, 45, 130 },
		en = { label = "Level Pre-2", desc = "High school (in progress)" }, jlpt = "≈ JLPT N1", tier = "Gold" },
	{ key = "K02", label = "2級",   desc = "高校卒業程度",        kanji = 2136, color = { 190, 45, 190 },
		en = { label = "Level 2", desc = "High school graduate" }, jlpt = "≈ JLPT N1", tier = "Platinum" },
	{ key = "KP1", label = "準1級", desc = "大学・一般程度",      kanji = 2997, color = { 140, 50, 220 },
		en = { label = "Level Pre-1", desc = "University / adult" }, jlpt = "beyond JLPT N1", tier = "Diamond" },
	{ key = "K01", label = "1級",   desc = "大学・一般程度",      kanji = 6357, color = { 70, 60, 225 },
		en = { label = "Level 1", desc = "University / adult · expert" }, jlpt = "beyond JLPT N1", tier = "Master" },
}

-- ───────────────────────────────────── 基本対戦ルール (旧互換は維持) ─────
GameConfig.ROUND_COUNT = 10        -- 1マッチの問題数
GameConfig.QUESTION_TIME = 12      -- 制限時間(秒)
GameConfig.INTRO_TIME = 3
GameConfig.REVEAL_TIME = 1.6
GameConfig.MAX_HP = 100
GameConfig.DMG_BASE = 20           -- 正答時の基本ダメージ
GameConfig.DMG_FAST_BONUS = 10     -- 3秒以内の正答ボーナス
GameConfig.DMG_FIRST_BONUS = 5     -- 一番乗りボーナス
GameConfig.QUEUE_TIMEOUT = 45      -- マッチが組まれなければ練習を勧める
GameConfig.ELO_K = 32
GameConfig.DEFAULT_RATING = 1000

-- ───────────────────────────────────── 超拡張バトルシステム ─────────────
GameConfig.BATTLE = {
	-- コンボ: 連続正解でダメージ倍率が上がる (見た目も派手に)
	COMBO_BONUS = { 0, 0, 4, 8, 14, 22 }, -- index = streak (1始まり), 0,0は1,2連鎖はボーナスなし, 3連鎖+4 ...
	COMBO_MULTIPLIER = { 1.0, 1.0, 1.15, 1.3, 1.5, 1.8, 2.0 }, -- 6連鎖以降は2倍で頭打ち

	-- パーフェクト (1.8秒以内) でさらに+8 & エフェクト
	PERFECT_WINDOW = 1.8,
	PERFECT_BONUS = 8,

	-- クリティカル: 正答時に確率で発生
	CRIT_CHANCE = 0.12, -- 12%
	CRIT_MULTIPLIER = 1.5,

	-- ガード: 両者正解時は受けるダメージ軽減
	GUARD_REDUCTION = 0.45, -- 45%カット

	-- シールド: 開幕1回だけ被ダメを半減する「見切り」 (Robuxでも追加購入可)
	START_SHIELD = true,
	SHIELD_REDUCTION = 0.5,

	-- 必殺ゲージ: 正解で+25, パーフェクトで+40, 誤答で-10, MAX100で発動可能
	ULT_GAIN_CORRECT = 25,
	ULT_GAIN_PERFECT = 40,
	ULT_GAIN_WRONG = -10,
	ULT_MAX = 100,
	ULT_DAMAGE = 40, -- 必殺の固定ダメージ (HPが低いほど演出強化)
	ULT_HEAL = 15,   -- おまけで自己回復

	-- 逆転ボーナス: HPが30以下で正解すると+5
	COMEBACK_HP = 30,
	COMEBACK_BONUS = 5,

	-- タイムアタックボーナス: 残り時間が多いほど追加 (最大+6)
	TIME_BONUS_MAX = 6,

	-- 連続誤答ペナルティ: 3連続誤答で相手に+5回復させてしまう
	MISS_STREAK_PENALTY = 3,
}

-- ───────────────────────────────────── ランク / ティア ─────────────────
GameConfig.RANKS = {
	{ key = "Bamboo",   labelJa = "竹",   labelEn = "Bamboo",   minRating = 0,    color = { 90, 185, 105 }, icon = "🎋" },
	{ key = "Bronze",   labelJa = "銅",   labelEn = "Bronze",   minRating = 1100, color = { 190, 155, 40 }, icon = "🥉" },
	{ key = "Silver",   labelJa = "銀",   labelEn = "Silver",   minRating = 1300, color = { 180, 180, 190 }, icon = "🥈" },
	{ key = "Gold",     labelJa = "金",   labelEn = "Gold",     minRating = 1500, color = { 245, 210, 90 }, icon = "🥇" },
	{ key = "Platinum", labelJa = "白金", labelEn = "Platinum", minRating = 1700, color = { 170, 220, 255 }, icon = "💎" },
	{ key = "Diamond",  labelJa = "金剛", labelEn = "Diamond",  minRating = 1900, color = { 140, 160, 255 }, icon = "🔷" },
	{ key = "Master",   labelJa = "名人", labelEn = "Master",   minRating = 2100, color = { 255, 90, 120 }, icon = "👑" },
	{ key = "Legend",   labelJa = "伝説", labelEn = "Legend",   minRating = 2400, color = { 255, 60, 60 }, icon = "🏆" },
}

-- ───────────────────────────────────── 経済・通貨 ─────────────────────
GameConfig.ECONOMY = {
	-- 通貨: Coins (無償) / Gems (有償/Robux由来)
	START_COINS = 300,
	START_GEMS = 10,

	-- 獲得
	REWARD_WIN = 45,
	REWARD_LOSE = 12,
	REWARD_DRAW = 20,
	REWARD_PERFECT = 8,
	REWARD_COMBO3 = 10,
	REWARD_DAILY_BONUS = 50, -- 初回勝利ボーナス

	-- 練習
	REWARD_PRACTICE_CORRECT = 2,
	REWARD_PRACTICE_STREAK5 = 15,

	-- コスト
	COST_HINT = 15,           -- 1問だけ誤答を1つ消す
	COST_SECOND_CHANCE = 80,  -- 死んでも1回だけHP30で復活 (対戦中)
	COST_SHIELD_REFILL = 35,  -- シールド再付与
	COST_REROLL_QUESTION = 20,-- この問題を引き直す (練習)
}

-- ───────────────────────────────────── 課金 (Developer Products / Game Passes)
-- IDはダミー (本番ではデベロッパーダッシュボードで発行して置換)
GameConfig.PRODUCTS = {
	-- Developer Products (何度でも買える)
	DEV = {
		{ id = 1830001, key = "coins_500",  labelJa = "500コイン", labelEn = "500 Coins",  coins = 500,  priceRobux = 49 },
		{ id = 1830002, key = "coins_1500", labelJa = "1500コイン",labelEn = "1500 Coins", coins = 1500, priceRobux = 129 },
		{ id = 1830003, key = "coins_4000", labelJa = "4000コイン",labelEn = "4000 Coins", coins = 4000, priceRobux = 299 },
		{ id = 1830004, key = "gems_100",   labelJa = "100ジェム", labelEn = "100 Gems",   gems = 100,  priceRobux = 99 },
		{ id = 1830005, key = "gems_550",   labelJa = "550ジェム", labelEn = "550 Gems",   gems = 550,  priceRobux = 499 },
		{ id = 1830006, key = "streak_saver", labelJa = "連勝キープ", labelEn = "Streak Saver", priceRobux = 29, descJa = "敗北時に連勝が減らない (1回分)", descEn = "Protects win streak once" },
		{ id = 1830007, key = "double_xp_1h", labelJa = "2倍XP 1時間", labelEn = "2x XP 1h", priceRobux = 39 },
		{ id = 1830008, key = "battle_pass_premium", labelJa = "バトルパス プレミアム", labelEn = "Battle Pass Premium", priceRobux = 399 },
	},
	-- Game Passes (永続)
	PASS = {
		{ id = 830001, key = "vip",          labelJa = "VIP",          labelEn = "VIP",          priceRobux = 299, perksJa = "毎日+100コイン / 専用ロビー / 金ネーム", perksEn = "+100 coins daily / VIP lobby / gold name" },
		{ id = 830002, key = "no_ads",       labelJa = "広告なし",     labelEn = "No Ads",       priceRobux = 149 },
		{ id = 830003, key = "arena_pack",   labelJa = "アリーナパック", labelEn = "Arena Pack", priceRobux = 199, descJa = "8種のアリーナスキン解放", descEn = "Unlock 8 arena skins" },
		{ id = 830004, key = "ultimate_pack",labelJa = "奥義パック",   labelEn = "Ultimate Pack",priceRobux = 249, descJa = "奥義演出3種+エモート5種", descEn = "3 ultimate FX + 5 emotes" },
	},
}

-- ───────────────────────────────────── 成長・バトルパス ─────────────────
GameConfig.PROGRESSION = {
	MAX_LEVEL = 100,
	XP_PER_WIN = 120,
	XP_PER_LOSE = 35,
	XP_PER_CORRECT = 18,
	XP_PERFECT_BONUS = 12,
	XP_DAILY_MISSION = 80,
	XP_WEEKLY_MISSION = 350,
	-- レベル必要XP: 100 + lv*20
	XP_TABLE = nil, -- 後で生成
	-- バトルパス: 30ティア、1ティア=200XP相当、フリートラック+プレミアム
	PASS_TIERS = 30,
	PASS_XP_PER_TIER = 200,
	PASS_SEASON_DAYS = 30,
}

do
	local t = {}
	for lv = 1, GameConfig.PROGRESSION.MAX_LEVEL do
		t[lv] = 100 + (lv - 1) * 22
	end
	GameConfig.PROGRESSION.XP_TABLE = t
end

GameConfig.PASS_REWARDS = {
	-- tier, free, premium (coins/gems/cosmetic/xpBoost)
	{ tier = 1,  free = { coins = 100 }, premium = { gems = 20, titleJa = "見習い", titleEn = "Apprentice" } },
	{ tier = 5,  free = { coins = 200 }, premium = { gems = 30, emote = "bow" } },
	{ tier = 10, free = { coins = 300, shield = 2 }, premium = { gems = 50, arena = "sakura" } },
	{ tier = 15, free = { coins = 400 }, premium = { gems = 70, titleJa = "達人", titleEn = "Master" } },
	{ tier = 20, free = { coins = 500, gems = 20 }, premium = { gems = 100, skin = "gold_kanji" } },
	{ tier = 25, free = { coins = 700 }, premium = { gems = 120, emote = "kiai" } },
	{ tier = 30, free = { coins = 1000, gems = 50 }, premium = { gems = 200, titleJa = "伝説", titleEn = "Legend", arena = "legend" } },
}

-- ───────────────────────────────────── デイリー / ミッション ────────────
GameConfig.DAILY = {
	REWARDS = { 20, 30, 50, 80, 120, 200, 350 }, -- 7日目が豪華
	BONUS_GEMS_DAY7 = 25,
}

GameConfig.MISSIONS = {
	DAILY = {
		{ key = "win1",  labelJa = "1勝する", labelEn = "Win 1 match", target = 1, rewardCoins = 30, rewardXp = 80 },
		{ key = "correct10", labelJa = "10問正解", labelEn = "10 correct answers", target = 10, rewardCoins = 25, rewardXp = 60 },
		{ key = "perfect3", labelJa = "パーフェクト3回", labelEn = "3 perfect answers", target = 3, rewardCoins = 35, rewardXp = 70 },
		{ key = "practice5", labelJa = "練習で5問正解", labelEn = "5 practice correct", target = 5, rewardCoins = 20, rewardXp = 50 },
	},
	WEEKLY = {
		{ key = "win10", labelJa = "10勝する", labelEn = "Win 10 matches", target = 10, rewardCoins = 200, rewardXp = 350 },
		{ key = "correct100", labelJa = "100問正解", labelEn = "100 correct", target = 100, rewardCoins = 150, rewardXp = 300 },
		{ key = "combo5", labelJa = "5連鎖を3回", labelEn = "3x 5-combo", target = 3, rewardCoins = 180, rewardXp = 320 },
	},
}

-- ───────────────────────────────────── コスメティック ─────────────────
GameConfig.COSMETICS = {
	TITLES = {
		{ key = "novice", labelJa = "初心", labelEn = "Novice", priceCoins = 0 },
		{ key = "apprentice", labelJa = "見習い", labelEn = "Apprentice", priceGems = 20 },
		{ key = "master", labelJa = "達人", labelEn = "Master", priceGems = 80 },
		{ key = "legend", labelJa = "伝説", labelEn = "Legend", priceGems = 200 },
		{ key = "oni", labelJa = "鬼", labelEn = "Oni", priceCoins = 500 },
		{ key = "kami", labelJa = "神", labelEn = "Kami", priceGems = 350 },
	},
	ARENAS = {
		{ key = "default", labelJa = "通常", labelEn = "Default", priceCoins = 0 },
		{ key = "sakura", labelJa = "桜", labelEn = "Sakura", priceCoins = 800 },
		{ key = "night", labelJa = "夜戦", labelEn = "Night", priceGems = 40 },
		{ key = "legend", labelJa = "伝説殿", labelEn = "Legend Hall", priceGems = 150 },
	},
	EMOTES = {
		{ key = "bow", labelJa = "礼", labelEn = "Bow", priceCoins = 200 },
		{ key = "kiai", labelJa = "気合", labelEn = "Kiai", priceGems = 30 },
		{ key = "gloat", labelJa = "ドヤ", labelEn = "Gloat", priceGems = 45 },
	},
}

-- ───────────────────────────────────── ショップ並び (表示用タブ) ─────
GameConfig.SHOP_TABS = { "coins", "gems", "boost", "cosmetic", "pass" }

-- ───────────────────────────────────── バランス調整用 ─────────────────
GameConfig.BALANCE_VERSION = 2 -- クライアントとサーバーで共有して不整合検出

function GameConfig.levelByKey(key)
	for _, lv in ipairs(GameConfig.LEVELS) do
		if lv.key == key then
			return lv
		end
	end
	return nil
end

function GameConfig.color3(lv)
	local c = lv.color
	return Color3.fromRGB(c[1], c[2], c[3])
end

function GameConfig.rankOf(rating)
	local best = GameConfig.RANKS[1]
	for _, r in ipairs(GameConfig.RANKS) do
		if rating >= r.minRating then
			best = r
		end
	end
	return best
end

function GameConfig.rankProgress(rating)
	-- 次のランクまでの進捗 0-1
	local cur = GameConfig.rankOf(rating)
	local idx = 1
	for i, r in ipairs(GameConfig.RANKS) do
		if r.key == cur.key then idx = i break end
	end
	local nxt = GameConfig.RANKS[idx + 1]
	if not nxt then return 1 end
	local span = nxt.minRating - cur.minRating
	if span <= 0 then return 1 end
	return math.clamp((rating - cur.minRating) / span, 0, 1)
end

return GameConfig
