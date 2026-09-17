--!nocheck
-- 漢字コンバット shared configuration (ReplicatedStorage.KKShared.GameConfig)
--
-- 競技性を壊さず長く遊べるように、対戦ルール・進行・ショップの定義を
-- ここに集約しています。Robux 商品 ID は公開するゲームごとに設定してください。

local GameConfig = {}

GameConfig.GAME_NAME = "漢字コンバット"
GameConfig.GAME_NAME_EN = "KANJI KOMBAT"

-- レベル定義。label/desc は日本語UI、en = { label, desc } は英語UI用、
-- jlpt は英語UI向けの「JLPT の目安」(あくまで目安。漢検の級とは別制度)。
GameConfig.LEVELS = {
	{ key = "K10", label = "10級",  desc = "小学校1年生修了程度", kanji = 80,   color = { 90, 185, 105 },
		en = { label = "Level 10", desc = "Grade 1 (elementary)" }, jlpt = "≈ JLPT N5" },
	{ key = "K09", label = "9級",   desc = "小学校2年生修了程度", kanji = 240,  color = { 110, 175, 70 },
		en = { label = "Level 9", desc = "Grade 2 (elementary)" }, jlpt = "≈ JLPT N5" },
	{ key = "K08", label = "8級",   desc = "小学校3年生修了程度", kanji = 440,  color = { 150, 165, 50 },
		en = { label = "Level 8", desc = "Grade 3 (elementary)" }, jlpt = "≈ JLPT N4" },
	{ key = "K07", label = "7級",   desc = "小学校4年生修了程度", kanji = 642, color = { 190, 155, 40 },
		en = { label = "Level 7", desc = "Grade 4 (elementary)" }, jlpt = "≈ JLPT N3" },
	{ key = "K06", label = "6級",   desc = "小学校5年生修了程度", kanji = 835, color = { 215, 130, 35 },
		en = { label = "Level 6", desc = "Grade 5 (elementary)" }, jlpt = "≈ JLPT N3" },
	{ key = "K05", label = "5級",   desc = "小学校6年生修了程度", kanji = 1026, color = { 235, 100, 30 },
		en = { label = "Level 5", desc = "Grade 6 (elementary)" }, jlpt = "≈ JLPT N2" },
	{ key = "K04", label = "4級",   desc = "中学校在学程度",      kanji = 1339, color = { 240, 70, 45 },
		en = { label = "Level 4", desc = "Junior high (in progress)" }, jlpt = "≈ JLPT N2" },
	{ key = "K03", label = "3級",   desc = "中学校卒業程度",      kanji = 1623, color = { 235, 50, 75 },
		en = { label = "Level 3", desc = "Junior high graduate" }, jlpt = "≈ JLPT N1" },
	{ key = "KP2", label = "準2級", desc = "高校在学程度",        kanji = 1951, color = { 220, 45, 130 },
		en = { label = "Level Pre-2", desc = "High school (in progress)" }, jlpt = "≈ JLPT N1" },
	{ key = "K02", label = "2級",   desc = "高校卒業程度",        kanji = 2136, color = { 190, 45, 190 },
		en = { label = "Level 2", desc = "High school graduate" }, jlpt = "≈ JLPT N1" },
	{ key = "KP1", label = "準1級", desc = "大学・一般程度",      kanji = 2997, color = { 140, 50, 220 },
		en = { label = "Level Pre-1", desc = "University / adult" }, jlpt = "beyond JLPT N1" },
	{ key = "K01", label = "1級",   desc = "大学・一般程度",      kanji = 6357, color = { 70, 60, 225 },
		en = { label = "Level 1", desc = "University / adult · expert" }, jlpt = "beyond JLPT N1" },
}

GameConfig.LOCALES = { "ja", "en" }
GameConfig.DEFAULT_LOCALE = "en"

-- ================================================================ battle
-- 1問ごとに同じ問題を同時に解く。勝敗は知識・速さ・スキル判断の合算。
GameConfig.ROUND_COUNT = 10
GameConfig.QUESTION_TIME = 12
GameConfig.INTRO_TIME = 3
GameConfig.REVEAL_TIME = 1.6
GameConfig.MAX_HP = 100
GameConfig.DMG_BASE = 20
GameConfig.DMG_FAST_BONUS = 10       -- 3秒以内
GameConfig.DMG_FIRST_BONUS = 5       -- 先に送信した正答
GameConfig.DMG_COMBO_STEP = 3        -- コンボ1段ごとのボーナス
GameConfig.DMG_COMBO_CAP = 5
GameConfig.DMG_FOCUS_MULTIPLIER = 1.35
GameConfig.SHIELD_REDUCTION = 0.5
GameConfig.ENERGY_MAX = 100
GameConfig.ENERGY_CORRECT = 20
GameConfig.ENERGY_FAST = 10
GameConfig.ENERGY_GUARD_COST = 30
GameConfig.ENERGY_FOCUS_COST = 40
GameConfig.GUARD_SHIELD = 40
GameConfig.QUESTION_GRACE = 0.25
GameConfig.QUEUE_TIMEOUT = 45
GameConfig.ELO_K = 32
GameConfig.DEFAULT_RATING = 1000

-- プレイヤーの腕前の可視化。課金で変わらない競技ランク。
GameConfig.RANKS = {
	{ key = "bronze", label = "木刀", en = "Wooden Blade", min = 0, color = { 160, 120, 80 } },
	{ key = "silver", label = "銀刀", en = "Silver Blade", min = 1100, color = { 180, 195, 215 } },
	{ key = "gold", label = "金刀", en = "Golden Blade", min = 1250, color = { 245, 205, 80 } },
	{ key = "platinum", label = "玉鋼", en = "Tamahagane", min = 1400, color = { 90, 220, 210 } },
	{ key = "master", label = "達人", en = "Master", min = 1600, color = { 220, 100, 255 } },
	{ key = "mythic", label = "漢字神", en = "Kanji Deity", min = 1800, color = { 255, 90, 120 } },
}

GameConfig.PROGRESSION = {
	XP_WIN = 180,
	XP_LOSS = 70,
	XP_CORRECT = 4,
	COINS_WIN = 55,
	COINS_LOSS = 18,
	COINS_PRACTICE = 2,
	DAILY_GOAL = 3,
}

-- ================================================================ monetization
--
-- 商品 ID は Roblox Creator Dashboard で作成した ID に差し替えてください。
-- 0 のままでもゲームは完全に遊べ、ショップには「準備中」と表示されます。
-- Robux 商品はコスメ・練習支援・ゲーム内通貨だけにし、対戦の正解を買えない設計です。
GameConfig.SHOP_ITEMS = {
	{
		key = "coin_spark",
		kind = "product",
		id = 0,
		robux = 25,
		icon = "✦",
		nameKey = "shopCoinSpark",
		descKey = "shopCoinSparkDesc",
		grant = { coins = 500 },
	},
	{
		key = "coin_burst",
		kind = "product",
		id = 0,
		robux = 99,
		icon = "✹",
		nameKey = "shopCoinBurst",
		descKey = "shopCoinBurstDesc",
		grant = { coins = 2400 },
	},
	{
		key = "vip_dojo",
		kind = "gamepass",
		id = 0,
		robux = 149,
		icon = "☯",
		nameKey = "shopVipDojo",
		descKey = "shopVipDojoDesc",
		grant = { item = "vip_dojo" },
	},
	{
		key = "neon_title",
		kind = "gamepass",
		id = 0,
		robux = 199,
		icon = "⚡",
		nameKey = "shopNeonTitle",
		descKey = "shopNeonTitleDesc",
		grant = { item = "neon_title" },
	},
	{
		key = "practice_pack",
		kind = "product",
		id = 0,
		robux = 49,
		icon = "📖",
		nameKey = "shopPracticePack",
		descKey = "shopPracticePackDesc",
		grant = { coins = 850, xp = 250 },
	},
}

function GameConfig.levelByKey(key)
	for _, lv in ipairs(GameConfig.LEVELS) do
		if lv.key == key then
			return lv
		end
	end
	return nil
end

function GameConfig.rankForRating(rating)
	local selected = GameConfig.RANKS[1]
	for _, rank in ipairs(GameConfig.RANKS) do
		if rating >= rank.min then
			selected = rank
		end
	end
	return selected
end

function GameConfig.color3(lv)
	local c = lv.color
	return Color3.fromRGB(c[1], c[2], c[3])
end

return GameConfig
