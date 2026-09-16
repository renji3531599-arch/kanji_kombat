--!nocheck
-- 多言語対応 (日本語 / 英語)。KKShared.I18n として共有される。
--
-- 方針:
--   * 端末のロケール (Player.LocaleId / LocalizationService.RobloxLocaleId) で自動判定し、
--     ja* なら日本語、それ以外は英語にフォールバックする。
--   * プレイヤーが手動で切り替えた場合はその選択を DataStore に保存して優先する。
--   * サーバーは文章を送らず「キー + パラメータ」を送る (送信側の環境に依存しない)。

local Config = require(script.Parent:WaitForChild("GameConfig"))

local I18n = {}

I18n.LOCALES = Config.LOCALES
I18n.DEFAULT = Config.DEFAULT_LOCALE or "en"

-- ================================================================ strings
-- {name} 形式のプレースホルダを I18n.t(key, {name = ...}) で置換する
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
	rating = {
		ja = "レート {rating}",
		en = "Rating {rating}",
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
		ja = "VS {opponent}（{reason}）\nレート {before} → {after}（{delta}）\n通算 {wins}勝 {losses}敗",
		en = "vs {opponent} ({reason})\nRating {before} → {after} ({delta})\n{wins}W / {losses}L",
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
}

-- ================================================================ state
local current = I18n.DEFAULT

local function normalize(code)
	code = tostring(code or ""):lower()
	if code:sub(1, 2) == "ja" then
		return "ja"
	end
	return "en"
end

-- "ja-jp" / "en-us" などのロケールID → "ja" / "en"
function I18n.localeFromId(id)
	return normalize(id)
end

function I18n.setLocale(code)
	current = normalize(code)
	return current
end

function I18n.getLocale()
	return current
end

-- 切り替え先 (ja <-> en)
function I18n.otherLocale(code)
	local c = normalize(code or current)
	return (c == "ja") and "en" or "ja"
end

function I18n.localeLabel(code)
	local c = normalize(code)
	return (c == "ja") and "日本語" or "English"
end

-- 端末ロケールの自動判定 (クライアントのみ。サーバーでは既定値を返す)
function I18n.detectLocale()
	local id = ""
	pcall(function()
		local Players = game:GetService("Players")
		local plr = Players and Players.LocalPlayer
		if plr and plr.LocaleId and plr.LocaleId ~= "" then
			id = plr.LocaleId
		else
			id = game:GetService("LocalizationService").RobloxLocaleId or ""
		end
	end)
	if id == "" then
		return nil, ""
	end
	return normalize(id), id
end

-- ================================================================ translate
function I18n.raw(key, locale)
	local entry = STRINGS[key]
	if not entry then
		return nil
	end
	return entry[normalize(locale or current)] or entry[I18n.DEFAULT] or key
end

function I18n.has(key)
	return STRINGS[key] ~= nil
end

-- 定義済みキーの一覧 (tools/test_luau.py の検証用)
function I18n.keys()
	local out = {}
	for k in pairs(STRINGS) do
		out[#out + 1] = k
	end
	return out
end

-- I18n.t("profileStats", { wins = 3, losses = 1, streak = 2 })
function I18n.t(key, params)
	local s = I18n.raw(key)
	if not s then
		warn("[I18n] missing key: " .. tostring(key))
		return tostring(key)
	end
	if params then
		s = (s:gsub("{([%w_]+)}", function(k)
			local v = params[k]
			return v ~= nil and tostring(v) or ("{" .. k .. "}")
		end))
	end
	return s
end

-- ================================================================ levels
function I18n.levelTitle(levelKey)
	local lv = Config.levelByKey(levelKey)
	if not lv then
		return tostring(levelKey)
	end
	if current == "en" and lv.en and lv.en.label then
		return lv.en.label
	end
	return lv.label
end

function I18n.levelDesc(levelKey)
	local lv = Config.levelByKey(levelKey)
	if not lv then
		return ""
	end
	local base
	if current == "en" and lv.en and lv.en.desc then
		base = lv.en.desc
	else
		base = lv.desc
	end
	-- 英語UIでは JLPT の目安も併記する
	if current == "en" and lv.jlpt and lv.jlpt ~= "" then
		return base .. " · " .. lv.jlpt
	end
	return base
end

-- 級の説明つき表記: 日本語「10級」/ 英語「Level 10 (Grade 1 · ≈ JLPT N5)」
function I18n.levelFull(levelKey)
	local t = I18n.levelTitle(levelKey)
	local d = I18n.levelDesc(levelKey)
	if d == "" then
		return t
	end
	return t .. " (" .. d .. ")"
end

-- 読みの表示: 英語UIでは「きょうしゅう / kyoushuu」のよう併記する
function I18n.reading(kana, romaji)
	if current == "en" and romaji and romaji ~= "" then
		return kana .. " / " .. romaji
	end
	return kana
end

return I18n
