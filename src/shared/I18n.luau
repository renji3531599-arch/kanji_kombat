--!nocheck
-- 多言語対応 (日本語 / 英語)。KKShared.I18n として共有される。
-- 超拡張版: ショップ・バトルパス・対戦演出の全文言をカバー

local Config = require(script.Parent:WaitForChild("GameConfig"))

local I18n = {}

I18n.LOCALES = Config.LOCALES
I18n.DEFAULT = Config.DEFAULT_LOCALE or "en"

-- ================================================================ strings
local STRINGS = {
	-- ---------------------------------------------------------- lobby / title
	title = {
		ja = "漢字コンバット",
		en = Config.GAME_NAME_EN or "KANJI KOMBAT",
	},
	subtitle = {
		ja = "読みオンリー対戦 〜 級を選んで対戦相手と即バトル！",
		en = "Kanji reading battles. Pick a level and fight instantly!",
	},
	splashSubtitle = {
		ja = "読みオンリー対戦 · 漢検10級〜1級 · 12,000問",
		en = "Kanji reading battles · Kanken levels 10 to 1 · 12,000 questions",
	},
	titleStart = {
		ja = "クリックでスタート",
		en = "Click to start",
	},
	levelsNote = {
		ja = "出題範囲：漢検10級〜1級・各1,000問（計12,000問）",
		en = "Levels follow Kanken (Japan Kanji Aptitude Test) grades 10 → 1, 1,000 questions each.",
	},
	profileLoading = {
		ja = "プロフィール読込中…",
		en = "Loading profile…",
	},
	profileStats = {
		ja = "通算 {wins}勝 {losses}敗　連続 {streak}",
		en = "{wins}W {losses}L · streak {streak}",
	},
	profileLevel = {
		ja = "Lv.{level}　XP {xp}/{next}",
		en = "Lv.{level}  XP {xp}/{next}",
	},
	rating = {
		ja = "レート {rating}",
		en = "Rating {rating}",
	},
	rankLabel = {
		ja = "ランク {rank} {icon}",
		en = "Rank {rank} {icon}",
	},
	levelInfo = {
		ja = "漢字 {kanji}字 / 1,000問",
		en = "1,000 questions · {kanji} kanji",
	},
	levelQueue = {
		ja = "対戦待ち {n}人",
		en = "{n} waiting now",
	},

	-- ---------------------------------------------------------- language switch
	languageButton = {
		ja = "🌐 English",
		en = "🌐 日本語",
	},
	languageChanged = {
		ja = "言語: 日本語",
		en = "Language: English",
	},
	languageChangedAuto = {
		ja = "言語: 日本語（端末設定から自動判定）",
		en = "Language: English (auto-detected)",
	},

	-- ---------------------------------------------------------- lobby buttons
	battleButton = {
		ja = "対戦エントリー",
		en = "Find a Match",
	},
	practiceButton = {
		ja = "練習",
		en = "Practice",
	},
	cancelButton = {
		ja = "キャンセル",
		en = "Cancel",
	},
	shopButton = {
		ja = "ショップ",
		en = "Shop",
	},
	passButton = {
		ja = "バトルパス",
		en = "Battle Pass",
	},
	missionButton = {
		ja = "ミッション",
		en = "Missions",
	},
	dailyButton = {
		ja = "デイリー",
		en = "Daily",
	},
	pickLevel = {
		ja = "級を選んでね！",
		en = "Pick a level first!",
	},
	selected = {
		ja = "{level}（{desc}）を選択中",
		en = "Selected: {level} — {desc}",
	},
	searching = {
		ja = "マッチング中…",
		en = "Searching for an opponent…",
	},
	toastSearching = {
		ja = "{level} の対戦相手を探しています…",
		en = "Looking for an opponent at {level}…",
	},
	toastNotEnoughCoins = {
		ja = "コインが足りない！",
		en = "Not enough coins!",
	},
	toastUltNotReady = {
		ja = "必殺ゲージがまだ足りない！",
		en = "Ultimate not ready!",
	},
	toastReward = {
		ja = "獲得！ {msg}",
		en = "Reward! {msg}",
	},

	-- ---------------------------------------------------------- currency
	coins = {
		ja = "コイン",
		en = "Coins",
	},
	gems = {
		ja = "ジェム",
		en = "Gems",
	},
	coinsShort = {
		ja = "{n}コイン",
		en = "{n} Coins",
	},
	gemsShort = {
		ja = "{n}ジェム",
		en = "{n} Gems",
	},
	shopTitle = {
		ja = "ショップ",
		en = "Shop",
	},
	shopCoinsTab = {
		ja = "コイン",
		en = "Coins",
	},
	shopGemsTab = {
		ja = "ジェム",
		en = "Gems",
	},
	shopBoostTab = {
		ja = "ブースト",
		en = "Boosts",
	},
	shopCosmeticTab = {
		ja = "きせかえ",
		en = "Cosmetics",
	},
	shopPassTab = {
		ja = "パス",
		en = "Pass",
	},
	buyButton = {
		ja = "買う",
		en = "Buy",
	},
	buyWithCoins = {
		ja = "{price}コインで買う",
		en = "Buy for {price} Coins",
	},
	buyWithGems = {
		ja = "{price}ジェムで買う",
		en = "Buy for {price} Gems",
	},
	buyWithRobux = {
		ja = "{price} Robuxで買う",
		en = "Buy for {price} Robux",
	},

	-- ---------------------------------------------------------- daily / pass / missions
	dailyTitle = {
		ja = "デイリーボーナス",
		en = "Daily Bonus",
	},
	dailyStreak = {
		ja = "{streak}日連続！",
		en = "{streak} day streak!",
	},
	dailyClaim = {
		ja = "受け取る",
		en = "Claim",
	},
	dailyClaimed = {
		ja = "受取済み",
		en = "Claimed",
	},
	passTitle = {
		ja = "バトルパス",
		en = "Battle Pass",
	},
	passTier = {
		ja = "ティア {tier}/{max}",
		en = "Tier {tier}/{max}",
	},
	passPremium = {
		ja = "プレミアム有効",
		en = "Premium Active",
	},
	passBuyPremium = {
		ja = "プレミアムを解放 (400 Robux)",
		en = "Unlock Premium (400 Robux)",
	},
	missionTitle = {
		ja = "ミッション",
		en = "Missions",
	},
	missionDaily = {
		ja = "デイリー",
		en = "Daily",
	},
	missionWeekly = {
		ja = "ウィークリー",
		en = "Weekly",
	},
	missionProgress = {
		ja = "{cur}/{target}",
		en = "{cur}/{target}",
	},
	missionComplete = {
		ja = "達成！ +{coins}コイン +{xp}XP",
		en = "Complete! +{coins} Coins +{xp} XP",
	},

	-- ---------------------------------------------------------- battle
	opponentLabel = {
		ja = "相手HP",
		en = "Opponent HP",
	},
	myHpLabel = {
		ja = "自分HP",
		en = "Your HP",
	},
	roundLabel = {
		ja = "ROUND {round}/{total}",
		en = "ROUND {round}/{total}",
	},
	suddenDeath = {
		ja = "サドンデス！",
		en = "SUDDEN DEATH!",
	},
	hintWord = {
		ja = "この言葉の読み方を選べ",
		en = "Choose the reading of this word",
	},
	hintKanji = {
		ja = "この漢字の読み方を選べ",
		en = "Choose the reading of this kanji",
	},
	preparing = {
		ja = "準備中…",
		en = "Get ready…",
	},
	answerCorrect = {
		ja = "正解！ 与ダメージ {dealt}",
		en = "Correct! +{dealt} damage",
	},
	answerWrong = {
		ja = "ざんねん… 正解は「{answer}」",
		en = "Missed — the answer is “{answer}”",
	},
	perfect = {
		ja = "パーフェクト！",
		en = "PERFECT!",
	},
	critical = {
		ja = "クリティカル！",
		en = "CRITICAL!",
	},
	comboLabel = {
		ja = "{n}コンボ！",
		en = "{n} COMBO!",
	},
	guarded = {
		ja = "ガード！",
		en = "Guarded!",
	},
	comeback = {
		ja = "逆転ボーナス！",
		en = "Comeback!",
	},
	ultReady = {
		ja = "必殺 準備完了！",
		en = "ULTIMATE READY!",
	},
	ultActivate = {
		ja = "必殺！",
		en = "ULTIMATE!",
	},
	shieldActive = {
		ja = "シールド展開中",
		en = "Shield Active",
	},
	shieldBroken = {
		ja = "シールド破損！",
		en = "Shield Broken!",
	},
	hintButton = {
		ja = "ヒント ({cost})",
		en = "Hint ({cost})",
	},
	ultButton = {
		ja = "必殺 ({pct}%)",
		en = "ULT ({pct}%)",
	},
	shieldButton = {
		ja = "シールド",
		en = "Shield",
	},
	rerollButton = {
		ja = "引き直し",
		en = "Reroll",
	},

	-- ---------------------------------------------------------- practice
	practiceTitle = {
		ja = "練習モード",
		en = "Practice Mode",
	},
	practiceSubtitle = {
		ja = "1人で読みトレーニング。連続正解をのばそう",
		en = "Solo reading drill — build your streak",
	},
	practiceStreak = {
		ja = "連続正解 {streak}",
		en = "Streak: {streak}",
	},
	practiceCorrect = {
		ja = "正解！ {answer}",
		en = "Correct! {answer}",
	},
	practiceWrong = {
		ja = "はずれ… 正解は「{answer}」",
		en = "Wrong… the answer is “{answer}”",
	},
	practiceExit = {
		ja = "練習をやめる",
		en = "Quit Practice",
	},
	practiceReroll = {
		ja = "次の問題",
		en = "Skip",
	},

	-- ---------------------------------------------------------- result
	resultWin = {
		ja = "WIN！",
		en = "YOU WIN!",
	},
	resultLose = {
		ja = "LOSE…",
		en = "YOU LOSE…",
	},
	resultDraw = {
		ja = "DRAW",
		en = "DRAW",
	},
	resultDetail = {
		ja = "VS {opponent}（{reason}）\nレート {before} → {after}（{delta}）\n通算 {wins}勝 {losses}敗　コイン+{coins}",
		en = "vs {opponent} ({reason})\nRating {before} → {after} ({delta})\n{wins}W / {losses}L  +{coins} Coins",
	},
	resultDetailDraw = {
		ja = "HPが同じまま10問終了",
		en = "Ten rounds finished with equal HP",
	},
	reasonMatch = {
		ja = "対戦",
		en = "head-to-head",
	},
	reasonKill = {
		ja = "KO勝ち",
		en = "KO",
	},
	reasonLeave = {
		ja = "不戦勝",
		en = "opponent left",
	},
	backToLobby = {
		ja = "ロビーへ",
		en = "Back to Lobby",
	},
	rematchButton = {
		ja = "再戦",
		en = "Rematch",
	},
	levelUp = {
		ja = "レベルアップ！ Lv.{level}",
		en = "Level Up! Lv.{level}",
	},
}

-- ================================================================ state
local current = I18n.DEFAULT

local function normalize(code)
	code = tostring(code or ""):lower()
	if code:sub(1, 2) == "ja" then return "ja" end
	return "en"
end

function I18n.localeFromId(id) return normalize(id) end
function I18n.setLocale(code) current = normalize(code) return current end
function I18n.getLocale() return current end
function I18n.otherLocale(code) local c = normalize(code or current) return (c == "ja") and "en" or "ja" end
function I18n.localeLabel(code) local c = normalize(code) return (c == "ja") and "日本語" or "English" end

function I18n.detectLocale()
	local id = ""
	pcall(function()
		local Players = game:GetService("Players")
		local plr = Players and Players.LocalPlayer
		if plr and plr.LocaleId and plr.LocaleId ~= "" then id = plr.LocaleId
		else id = game:GetService("LocalizationService").RobloxLocaleId or "" end
	end)
	if id == "" then return nil, "" end
	return normalize(id), id
end

function I18n.raw(key, locale)
	local entry = STRINGS[key]
	if not entry then return nil end
	return entry[normalize(locale or current)] or entry[I18n.DEFAULT] or key
end
function I18n.has(key) return STRINGS[key] ~= nil end
function I18n.keys() local out={} for k in pairs(STRINGS) do out[#out+1]=k end return out end
function I18n.t(key, params)
	local s = I18n.raw(key)
	if not s then warn("[I18n] missing key: "..tostring(key)) return tostring(key) end
	if params then s = (s:gsub("{([%w_]+)}", function(k) local v=params[k] return v~=nil and tostring(v) or ("{"..k.."}") end)) end
	return s
end

function I18n.levelTitle(levelKey)
	local lv = Config.levelByKey(levelKey)
	if not lv then return tostring(levelKey) end
	if current == "en" and lv.en and lv.en.label then return lv.en.label end
	return lv.label
end
function I18n.levelDesc(levelKey)
	local lv = Config.levelByKey(levelKey)
	if not lv then return "" end
	local base
	if current == "en" and lv.en and lv.en.desc then base = lv.en.desc else base = lv.desc end
	if current == "en" and lv.jlpt and lv.jlpt ~= "" then return base .. " · " .. lv.jlpt end
	return base
end
function I18n.levelFull(levelKey)
	local t = I18n.levelTitle(levelKey)
	local d = I18n.levelDesc(levelKey)
	if d == "" then return t end
	return t .. " (" .. d .. ")"
end
function I18n.reading(kana, romaji)
	if current == "en" and romaji and romaji ~= "" then return kana .. " / " .. romaji end
	return kana
end

return I18n
