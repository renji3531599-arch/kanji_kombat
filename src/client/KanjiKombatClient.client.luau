--!nonstrict
-- Kanji Kombat client (bilingual: 日本語 / English)
--
-- 言語は端末ロケール (Player.LocaleId) から自動判定し、
-- ロビー右上の 🌐 ボタンで手動切り替えもできる (選択はサーバーに保存)。
-- 読みの選択肢は英語UIのときローマ字 + かなを併記する。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LocalizationService = game:GetService("LocalizationService")

local UiKit = require(script.Parent:WaitForChild("ClientModules"):WaitForChild("UiKit"))
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))
local I18n = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("I18n"))
local Romaji = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("Romaji"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local S2C = remotes:WaitForChild("ServerToClient")
local C2S = remotes:WaitForChild("ClientToServer")
local GetProfileRF = remotes:WaitForChild("GetProfile")

local player = Players.LocalPlayer

local COL_BG = Color3.fromRGB(22, 20, 30)
local COL_CARD = Color3.fromRGB(34, 32, 44)
local COL_GOLD = Color3.fromRGB(245, 210, 90)
local COL_GOOD = Color3.fromRGB(90, 220, 120)
local COL_BAD = Color3.fromRGB(235, 80, 90)
local COL_TEXT = Color3.fromRGB(238, 238, 246)
local COL_DIM = Color3.fromRGB(150, 150, 170)
local COL_BTN = Color3.fromRGB(45, 43, 60)

-- ================================================================ locale
-- "auto" = 端末ロケールから自動判定 / "manual" = 🌐 ボタンで選択 (保存される)
local localeSource = "auto"
local serverLocale = nil

local function applyLocale(code)
	I18n.setLocale(code)
end

local function detectInitialLocale()
	local code = I18n.detectLocale()
	return code or Config.DEFAULT_LOCALE or "en"
end

applyLocale(detectInitialLocale())

local function pushLocaleToServer()
	pcall(function()
		C2S:FireServer({ action = "setLocale", locale = I18n.getLocale(), source = localeSource })
	end)
end

local screen = UiKit.mk("ScreenGui", {
	Name = "KanjiKombatUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

local T = {} -- [name] = TextLabel (retranslate で一括更新)

-- 先に宣言しておく (UI構築中のコールバックからも参照する)
local renderLevelCards, renderStatus, renderProfile, renderHp
local renderQuestion, renderPractice, renderResult, retranslate

-- ================================================================ lobby
local lobby = UiKit.mk("Frame", {
	Name = "Lobby",
	Size = UDim2.fromOffset(880, 700),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COL_BG,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
}, screen)
UiKit.corner(lobby, 18)
UiKit.stroke(lobby, Color3.fromRGB(120, 60, 70), 2, 0.15)

-- 小さい画面でも収まるようにスケール (モバイル対応)
local lobbyScale = UiKit.mk("UIScale", { Scale = 1, Parent = lobby })
local camera = workspace.CurrentCamera
local function fitLobby()
	local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local s = math.min(vp.X / 920, vp.Y / 740)
	lobbyScale.Scale = math.clamp(s, 0.5, 1)
end
fitLobby()
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitLobby)
end

T.title = UiKit.label({
	Size = UDim2.new(1, -220, 0, 52), Position = UDim2.fromOffset(100, 10),
	Font = Enum.Font.GothamBlack, TextColor3 = COL_GOLD,
}, lobby)
T.subtitle = UiKit.label({
	Size = UDim2.new(1, -40, 0, 22), Position = UDim2.new(0, 20, 0, 64),
	Font = Enum.Font.Gotham, TextColor3 = COL_DIM,
}, lobby)
T.levelsNote = UiKit.label({
	Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 20, 0, 86),
	Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(120, 120, 145),
	TextSize = 14, TextScaled = false,
}, lobby)
T.profileChip = UiKit.label({
	Size = UDim2.new(1, -40, 0, 20), Position = UDim2.new(0, 20, 0, 110),
	Font = Enum.Font.Gotham, TextColor3 = COL_TEXT, TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 15, TextScaled = false,
}, lobby)

local langButton = UiKit.button({
	Size = UDim2.fromOffset(160, 32), Position = UDim2.new(1, -180, 0, 12),
	BackgroundColor3 = Color3.fromRGB(60, 70, 105), TextSize = 15, TextScaled = false,
}, lobby)

T.status = UiKit.label({
	Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0, 20, 1, -124),
	Font = Enum.Font.Gotham, TextColor3 = COL_GOLD, TextSize = 17, TextScaled = false,
}, lobby)

local levelCards = {} -- [key] = { frame, title, desc, rating, info, queue }
local queueCounts = {}
local selectedKey = nil

local grid = UiKit.mk("Frame", {
	Size = UDim2.new(1, -40, 1, -250), Position = UDim2.fromOffset(20, 140),
	BackgroundTransparency = 1,
}, lobby)
UiKit.mk("UIGridLayout", {
	CellSize = UDim2.fromOffset(202, 126),
	CellPadding = UDim2.fromOffset(9, 9),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = grid,
})

local function buildLevelCards()
	for i, lv in ipairs(Config.LEVELS) do
		local card = UiKit.mk("Frame", {
			Name = "Card_" .. lv.key,
			BackgroundColor3 = COL_CARD,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, grid)
		UiKit.corner(card, 10)
		local col = Config.color3(lv)
		UiKit.mk("Frame", {
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = col,
			BorderSizePixel = 0,
		}, card)
		local title = UiKit.label({
			Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 12),
			TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local desc = UiKit.label({
			Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 42),
			Font = Enum.Font.Gotham, TextColor3 = COL_DIM,
			TextSize = 13, TextScaled = false, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		}, card)
		local rating = UiKit.label({
			Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 74),
			Font = Enum.Font.GothamBold, TextColor3 = COL_TEXT,
			TextSize = 14, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local info = UiKit.label({
			Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 96),
			Font = Enum.Font.Gotham, TextColor3 = COL_GOLD,
			TextSize = 13, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local btn = UiKit.mk("TextButton", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
		}, card)
		btn.MouseButton1Click:Connect(function()
			selectedKey = lv.key
			for k, c in pairs(levelCards) do
				local isSel = (k == lv.key)
				c.frame.BackgroundTransparency = isSel and 0.5 or 0
				c.frame.BackgroundColor3 = isSel and Color3.fromRGB(70, 55, 90) or COL_CARD
			end
			renderStatus()
		end)
		levelCards[lv.key] = {
			frame = card, title = title, desc = desc, rating = rating, info = info,
		}
	end
end
buildLevelCards()

local battleButton = UiKit.button({
	Size = UDim2.fromOffset(200, 46), Position = UDim2.new(0, 20, 1, -70),
	BackgroundColor3 = Color3.fromRGB(170, 45, 60),
}, lobby)
local practiceButton = UiKit.button({
	Size = UDim2.fromOffset(140, 46), Position = UDim2.new(0, 232, 1, -70),
	BackgroundColor3 = Color3.fromRGB(60, 110, 170),
}, lobby)
local cancelButton = UiKit.button({
	Size = UDim2.fromOffset(140, 46), Position = UDim2.new(0, 384, 1, -70),
	BackgroundColor3 = Color3.fromRGB(70, 70, 90), Visible = false,
}, lobby)

-- ================================================================ battle
local battle = UiKit.mk("Frame", {
	Name = "Battle", Visible = false, Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COL_BG, BackgroundTransparency = 0.25, BorderSizePixel = 0,
}, screen)

local opName = UiKit.label({
	Size = UDim2.fromOffset(360, 26), Position = UDim2.new(0.5, -180, 0, 18),
	Font = Enum.Font.GothamBold, Text = "",
}, battle)

-- HPバー (名前 + 数値を内蔵)
local function makeHpBar(size, position, color)
	local holder, fill = UiKit.hpBar(battle, size, position, color, Vector2.new(0, 0))
	local name = UiKit.label({
		Size = UDim2.new(0.6, -16, 1, 0), Position = UDim2.fromOffset(12, 0),
		Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(245, 245, 250),
		TextSize = 14, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	}, holder)
	local value = UiKit.label({
		Size = UDim2.new(0.4, -18, 1, 0), Position = UDim2.new(0.6, 6, 0, 0),
		Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(245, 245, 250),
		TextSize = 14, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
	}, holder)
	return { holder = holder, fill = fill, name = name, value = value }
end

local opHp = makeHpBar(UDim2.fromOffset(560, 22), UDim2.new(0.5, -280, 0, 50), COL_BAD)
local myHp = makeHpBar(UDim2.fromOffset(560, 24), UDim2.new(0.5, -280, 1, -76), COL_GOOD)

local roundLbl = UiKit.label({
	Size = UDim2.fromOffset(300, 30), Position = UDim2.new(0.5, -150, 0, 82),
	Font = Enum.Font.GothamBold, TextColor3 = COL_DIM, Text = "",
}, battle)

local promptCard = UiKit.mk("Frame", {
	Size = UDim2.fromOffset(680, 190), Position = UDim2.new(0.5, -340, 0, 126),
	BackgroundColor3 = COL_CARD, BorderSizePixel = 0,
}, battle)
UiKit.corner(promptCard, 14)
UiKit.stroke(promptCard, Color3.fromRGB(120, 90, 100), 2, 0.2)
local promptText = UiKit.label({
	Size = UDim2.new(1, -30, 1, -46), Position = UDim2.fromOffset(15, 8),
	Font = Enum.Font.GothamBold, TextColor3 = COL_TEXT, Text = "",
}, promptCard)
local promptHint = UiKit.label({
	Name = "Hint", Size = UDim2.new(1, -30, 0, 30), Position = UDim2.new(0, 15, 1, -38),
	Font = Enum.Font.Gotham, TextColor3 = COL_DIM,
	TextSize = 17, TextScaled = false, TextWrapped = true, Text = "",
}, promptCard)

local timerHolder = UiKit.mk("Frame", {
	Size = UDim2.fromOffset(680, 12), Position = UDim2.new(0.5, -340, 0, 330),
	BackgroundColor3 = Color3.fromRGB(25, 25, 32), BorderSizePixel = 0,
}, battle)
UiKit.corner(timerHolder, 6)
local timerFill = UiKit.mk("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = COL_GOLD, BorderSizePixel = 0,
}, timerHolder)
UiKit.corner(timerFill, 6)

-- 選択肢: 英語UIでは ローマ字 (大) + かな (小) の2段表示
local function makeChoiceButton(parent, position, size)
	local btn = UiKit.button({
		Size = size, Position = position, BackgroundColor3 = COL_BTN,
	}, parent)
	btn.Text = ""
	local main = UiKit.label({
		Size = UDim2.new(1, -20, 1, -8), Position = UDim2.new(0, 10, 0, 4),
		Font = Enum.Font.GothamBold, TextColor3 = COL_TEXT, ZIndex = 2, Text = "",
	}, btn)
	local sub = UiKit.label({
		Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, -24),
		Font = Enum.Font.Gotham, TextColor3 = COL_DIM,
		TextSize = 15, TextScaled = false, ZIndex = 2, Visible = false, Text = "",
	}, btn)
	return { button = btn, main = main, sub = sub }
end

local choiceButtons = {}
for i = 1, 4 do
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	choiceButtons[i] = makeChoiceButton(battle,
		UDim2.new(0.5, -335 + col * 340, 0, 358 + row * 76),
		UDim2.fromOffset(330, 66))
end

local suddenLbl = UiKit.label({
	Size = UDim2.fromOffset(400, 34), Position = UDim2.new(0.5, -200, 1, -122),
	Font = Enum.Font.GothamBold, TextColor3 = COL_BAD, Visible = false,
}, battle)

-- ================================================================ practice
local prac = UiKit.mk("Frame", {
	Name = "Practice", Visible = false, Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COL_BG, BackgroundTransparency = 0.25, BorderSizePixel = 0,
}, screen)
local pracTitle = UiKit.label({
	Size = UDim2.fromOffset(600, 32), Position = UDim2.new(0.5, -300, 0, 20),
	Font = Enum.Font.GothamBold, TextColor3 = COL_GOLD, Text = "",
}, prac)
local pracSub = UiKit.label({
	Size = UDim2.fromOffset(600, 20), Position = UDim2.new(0.5, -300, 0, 54),
	Font = Enum.Font.Gotham, TextColor3 = COL_DIM, TextSize = 14, TextScaled = false, Text = "",
}, prac)
local pracStreak = UiKit.label({
	Size = UDim2.fromOffset(600, 26), Position = UDim2.new(0.5, -300, 0, 78),
	Font = Enum.Font.Gotham, TextColor3 = COL_TEXT, TextSize = 18, TextScaled = false, Text = "",
}, prac)
local pracCard = UiKit.mk("Frame", {
	Size = UDim2.fromOffset(680, 160), Position = UDim2.new(0.5, -340, 0, 116),
	BackgroundColor3 = COL_CARD, BorderSizePixel = 0,
}, prac)
UiKit.corner(pracCard, 14)
local pracText = UiKit.label({
	Size = UDim2.new(1, -30, 1, -20), Position = UDim2.fromOffset(15, 10),
	Font = Enum.Font.GothamBold, TextColor3 = COL_TEXT, Text = "",
}, pracCard)
local pracChoices = {}
for i = 1, 4 do
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	pracChoices[i] = makeChoiceButton(prac,
		UDim2.new(0.5, -335 + col * 340, 0, 300 + row * 74),
		UDim2.fromOffset(330, 64))
end
local pracFeedback = UiKit.label({
	Size = UDim2.fromOffset(680, 46), Position = UDim2.new(0.5, -340, 0, 452),
	Font = Enum.Font.GothamBold, TextColor3 = COL_GOOD,
	TextSize = 19, TextScaled = false, TextWrapped = true, Text = "",
}, prac)
local pracExit = UiKit.button({
	Size = UDim2.fromOffset(180, 44), Position = UDim2.new(0.5, -90, 1, -70),
	BackgroundColor3 = Color3.fromRGB(70, 70, 90),
}, prac)

-- ================================================================ result / overlay
local result = UiKit.mk("Frame", {
	Name = "Result", Visible = false, Size = UDim2.fromOffset(480, 280),
	Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COL_CARD, BorderSizePixel = 0, ZIndex = 5,
}, screen)
UiKit.corner(result, 16)
UiKit.stroke(result, COL_GOLD, 2, 0.2)
local resultTitle = UiKit.label({
	Size = UDim2.new(1, -30, 0, 80), Position = UDim2.fromOffset(15, 20),
	Font = Enum.Font.GothamBlack, Text = "", ZIndex = 6,
}, result)
local resultDetail = UiKit.label({
	Size = UDim2.new(1, -30, 0, 90), Position = UDim2.new(0, 15, 0, 108),
	Font = Enum.Font.Gotham, TextColor3 = COL_TEXT,
	TextSize = 17, TextScaled = false, TextWrapped = true, Text = "", ZIndex = 6,
}, result)
local resultOk = UiKit.button({
	Size = UDim2.fromOffset(180, 46), Position = UDim2.new(0.5, -90, 1, -62),
	BackgroundColor3 = Color3.fromRGB(170, 45, 60), ZIndex = 6,
}, result)

local toastLbl = UiKit.label({
	Size = UDim2.fromOffset(600, 34), Position = UDim2.new(0.5, -300, 0, 110),
	Font = Enum.Font.GothamBold, TextColor3 = COL_GOLD,
	BackgroundTransparency = 1, Text = "", ZIndex = 10,
}, screen)
local toastToken = 0
local function toast(msg)
	toastToken = toastToken + 1
	local my = toastToken
	toastLbl.Text = msg
	task.delay(2.8, function()
		if toastToken == my then
			toastLbl.Text = ""
		end
	end)
end


-- ================================================================ title splash
-- 起動時に言語に応じたタイトルを見せる (英語圏では "KANJI KOMBAT" がメイン)
local splash = UiKit.mk("Frame", {
	Name = "TitleSplash", Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(12, 10, 16), BackgroundTransparency = 0.02,
	BorderSizePixel = 0, ZIndex = 20,
}, screen)
local splashTitle = UiKit.label({
	Size = UDim2.new(1, -40, 0, 130), Position = UDim2.new(0, 20, 0.5, -180),
	Font = Enum.Font.GothamBlack, TextColor3 = COL_GOLD, ZIndex = 21,
}, splash)
local splashSub = UiKit.label({
	Size = UDim2.new(1, -40, 0, 34), Position = UDim2.new(0, 20, 0.5, -30),
	Font = Enum.Font.Gotham, TextColor3 = COL_TEXT,
	TextSize = 20, TextScaled = false, ZIndex = 21,
}, splash)
local splashNote = UiKit.label({
	Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0, 20, 0.5, 20),
	Font = Enum.Font.Gotham, TextColor3 = COL_DIM,
	TextSize = 16, TextScaled = false, ZIndex = 21,
}, splash)
local splashHint = UiKit.label({
	Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0, 20, 1, -80),
	Font = Enum.Font.Gotham, TextColor3 = COL_DIM,
	TextSize = 16, TextScaled = false, ZIndex = 21,
}, splash)
local splashClick = UiKit.mk("TextButton", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 21,
}, splash)

local splashGone = false
local function hideSplash()
	if splashGone then
		return
	end
	splashGone = true
	local tw = TweenService:Create(splash, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
	tw:Play()
	for _, lbl in ipairs({ splashTitle, splashSub, splashNote, splashHint }) do
		TweenService:Create(lbl, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	end
	task.delay(0.55, function()
		splash.Visible = false
	end)
end
splashClick.MouseButton1Click:Connect(hideSplash)
task.delay(4, hideSplash)

local function renderSplash()
	splashTitle.Text = I18n.t("title")
	splashSub.Text = I18n.t("splashSubtitle")
	splashNote.Text = I18n.t(localeSource == "manual" and "languageChanged" or "languageChangedAuto")
	splashHint.Text = I18n.t("titleStart")
end

-- ================================================================ state
local profile = nil
local curRound = 0
local answerLocked = false
local practiceLocked = false
local queueing = false
local curQ = nil        -- 現在の対戦問題 (言語切替時の再描画用)
local curAnswer = nil   -- 直近の正誤結果
local curPracQ = nil
local curPracResult = nil
local curResultData = nil
local pracLevelKey = nil
local pracStreakValue = 0
local hpMe, hpOp = Config.MAX_HP, Config.MAX_HP

-- ================================================================ text helpers
local function setChoiceText(choice, primary, secondary)
	choice.button.Text = ""
	choice.main.Text = primary
	choice.sub.Text = secondary or ""
	if secondary and secondary ~= "" then
		choice.main.Size = UDim2.new(1, -20, 0, 34)
		choice.main.Position = UDim2.new(0, 10, 0, 6)
		choice.sub.Visible = true
	else
		choice.main.Size = UDim2.new(1, -20, 1, -8)
		choice.main.Position = UDim2.new(0, 10, 0, 4)
		choice.sub.Visible = false
	end
end

local function resetChoiceColors(list)
	for _, c in ipairs(list) do
		c.button.AutoButtonColor = true
		c.button.BackgroundColor3 = COL_BTN
		c.sub.TextColor3 = COL_DIM
	end
end

-- かな1つ分のローマ字 (英語UI用)
local function romaji(kana)
	return Romaji.convert(kana)
end

-- 選択肢4つ分のローマ字 (じ/ぢ など、同じ表記になる場合は自動で別表記にする)
local function romajiList(list)
	local kana = {}
	for i = 1, 4 do
		kana[i] = (list and list[i]) or ""
	end
	return Romaji.convertMany(kana)
end

local function readingText(kana)
	if I18n.getLocale() == "en" then
		return I18n.reading(kana, romaji(kana))
	end
	return kana
end

function renderLevelCards()
	for key, card in pairs(levelCards) do
		card.title.Text = I18n.levelTitle(key)
		card.desc.Text = I18n.levelDesc(key)
		local lv = Config.levelByKey(key)
		local n = queueCounts[key] or 0
		if n > 0 then
			card.info.Text = I18n.t("levelQueue", { n = n })
			card.info.TextColor3 = COL_GOOD
		else
			card.info.Text = I18n.t("levelInfo", { kanji = lv and lv.kanji or 0 })
			card.info.TextColor3 = COL_GOLD
		end
		local r = (profile and profile.ratings and profile.ratings[key]) or Config.DEFAULT_RATING
		card.rating.Text = I18n.t("rating", { rating = r })
	end
end

function renderStatus()
	if not selectedKey then
		T.status.Text = ""
		return
	end
	T.status.Text = I18n.t("selected", {
		level = I18n.levelTitle(selectedKey),
		desc = I18n.levelDesc(selectedKey),
	})
end

function renderProfile()
	if not profile then
		T.profileChip.Text = I18n.t("profileLoading")
		return
	end
	T.profileChip.Text = I18n.t("profileStats", {
		wins = profile.wins or 0,
		losses = profile.losses or 0,
		streak = profile.streak or 0,
	})
end

function renderHp()
	opHp.name.Text = I18n.t("opponentLabel")
	myHp.name.Text = I18n.t("myHpLabel")
	opHp.value.Text = hpOp .. " / " .. Config.MAX_HP
	myHp.value.Text = hpMe .. " / " .. Config.MAX_HP
end

function renderQuestion()
	if not curQ then
		return
	end
	promptText.Text = curQ.isKanji and ("『" .. curQ.prompt .. "』") or curQ.prompt
	local readings = {}
	if I18n.getLocale() == "en" then
		readings = romajiList(curQ.choices) -- じ/ぢ などが同じ表記にならないように
	end
	for i, choice in ipairs(choiceButtons) do
		local kana = curQ.choices[i] or ""
		if I18n.getLocale() == "en" then
			setChoiceText(choice, readings[i] or romaji(kana), kana)
		else
			setChoiceText(choice, kana, nil)
		end
	end
	if curAnswer then
		local kana = curQ.choices[curAnswer.correctIdx] or "?"
		if curAnswer.correct then
			promptHint.TextColor3 = COL_GOOD
			promptHint.Text = I18n.t("answerCorrect", { dealt = curAnswer.dealt or 0 })
		else
			promptHint.TextColor3 = COL_BAD
			promptHint.Text = I18n.t("answerWrong", { answer = readingText(kana) })
		end
	else
		promptHint.TextColor3 = COL_DIM
		promptHint.Text = I18n.t(curQ.isKanji and "hintKanji" or "hintWord")
	end
	roundLbl.Text = I18n.t("roundLabel", { round = curQ.round, total = curQ.total })
end

function renderPractice()
	pracTitle.Text = I18n.t("practiceTitle")
		.. (pracLevelKey and (" · " .. I18n.levelTitle(pracLevelKey)) or "")
	pracSub.Text = I18n.t("practiceSubtitle")
	pracStreak.Text = I18n.t("practiceStreak", { streak = pracStreakValue })
	if not curPracQ then
		return
	end
	pracText.Text = curPracQ.isKanji and ("『" .. curPracQ.prompt .. "』") or curPracQ.prompt
	local readings = {}
	if I18n.getLocale() == "en" then
		readings = romajiList(curPracQ.choices)
	end
	for i, choice in ipairs(pracChoices) do
		local kana = curPracQ.choices[i] or ""
		if I18n.getLocale() == "en" then
			setChoiceText(choice, readings[i] or romaji(kana), kana)
		else
			setChoiceText(choice, kana, nil)
		end
	end
	if curPracResult then
		local kana = curPracQ.choices[curPracResult.correctIdx] or "?"
		if curPracResult.correct then
			pracFeedback.TextColor3 = COL_GOOD
			pracFeedback.Text = I18n.t("practiceCorrect", { answer = readingText(kana) })
		else
			pracFeedback.TextColor3 = COL_BAD
			pracFeedback.Text = I18n.t("practiceWrong", { answer = readingText(kana) })
		end
	end
end

function renderResult()
	if not curResultData then
		return
	end
	local d = curResultData
	if d.draw then
		resultTitle.Text = I18n.t("resultDraw")
		resultTitle.TextColor3 = COL_DIM
		resultDetail.Text = I18n.t("resultDetailDraw")
		return
	end
	local reason = I18n.t(d.reason == "leave" and "reasonLeave" or (d.reason == "KO" and "reasonKill" or "reasonMatch"))
	local delta = d.delta or 0
	resultTitle.Text = I18n.t(d.win and "resultWin" or "resultLose")
	resultTitle.TextColor3 = d.win and COL_GOLD or COL_BAD
	resultDetail.Text = I18n.t("resultDetail", {
		opponent = d.opponent or "?",
		reason = reason,
		before = (d.rating or Config.DEFAULT_RATING) - delta,
		after = d.rating or Config.DEFAULT_RATING,
		delta = string.format("%+d", delta),
		wins = d.wins or 0,
		losses = d.losses or 0,
	})
end

-- 言語が変わったときに呼ぶ (静的テキスト + 動的表示をまとめて再構築)
function retranslate()
	T.title.Text = I18n.t("title")
	T.subtitle.Text = I18n.t("subtitle")
	T.levelsNote.Text = I18n.t("levelsNote")
	langButton.Text = I18n.t("languageButton")
	battleButton.Text = I18n.t("battleButton")
	practiceButton.Text = I18n.t("practiceButton")
	cancelButton.Text = I18n.t("cancelButton")
	pracExit.Text = I18n.t("practiceExit")
	resultOk.Text = I18n.t("backToLobby")
	suddenLbl.Text = I18n.t("suddenDeath")
	if not curQ then
		roundLbl.Text = I18n.t("preparing")
	end
	if queueing then
		T.status.Text = I18n.t("searching")
	end
	renderSplash()
	renderLevelCards()
	renderStatus()
	renderProfile()
	renderHp()
	renderQuestion()
	renderPractice()
	renderResult()
end

local function refreshProfile()
	task.spawn(function()
		local ok, p = pcall(function()
			return GetProfileRF:InvokeServer()
		end)
		if ok and type(p) == "table" then
			profile = p
			renderProfile()
			renderLevelCards()
			-- 保存された手動設定があれば自動判定より優先する
			if localeSource == "auto" and type(p.locale) == "string" and p.locale ~= "" then
				serverLocale = I18n.localeFromId(p.locale)
				if serverLocale ~= I18n.getLocale() then
					localeSource = "manual"
					applyLocale(serverLocale)
					retranslate()
					toast(I18n.t("languageChanged"))
					return
				end
			end
			pushLocaleToServer() -- 端末ロケールをサーバーにも伝える (leaderstats の表記用)
		end
	end)
end

local function setQueueing(v)
	queueing = v
	battleButton.Visible = not v
	practiceButton.Visible = not v
	cancelButton.Visible = v
	if v then
		T.status.Text = I18n.t("searching")
	elseif not selectedKey then
		T.status.Text = ""
	end
end

local function showLobby()
	battle.Visible = false
	prac.Visible = false
	result.Visible = false
	lobby.Visible = true
	refreshProfile()
end

-- ================================================================ language toggle
langButton.MouseButton1Click:Connect(function()
	local nextLocale = I18n.otherLocale(I18n.getLocale())
	localeSource = "manual"
	serverLocale = nextLocale
	applyLocale(nextLocale)
	retranslate()
	toast(I18n.t("languageChanged"))
	pushLocaleToServer()
end)

-- 端末の言語設定が変わったら (自動判定モードのときだけ) 追従する
local function onSystemLocaleChanged()
	if localeSource ~= "auto" then
		return
	end
	local code = I18n.detectLocale()
	if code and code ~= I18n.getLocale() then
		applyLocale(code)
		retranslate()
		toast(I18n.t("languageChangedAuto"))
	end
end
pcall(function()
	player:GetPropertyChangedSignal("LocaleId"):Connect(onSystemLocaleChanged)
end)
pcall(function()
	LocalizationService:GetPropertyChangedSignal("RobloxLocaleId"):Connect(onSystemLocaleChanged)
end)

-- ================================================================ battle flow
local function startTimer(seconds)
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.BackgroundColor3 = COL_GOLD
	local tween = TweenService:Create(timerFill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
	tween:Play()
end

battleButton.MouseButton1Click:Connect(function()
	if not selectedKey then
		toast(I18n.t("pickLevel"))
		return
	end
	C2S:FireServer({ action = "queue", levelKey = selectedKey })
	setQueueing(true)
end)
practiceButton.MouseButton1Click:Connect(function()
	if not selectedKey then
		toast(I18n.t("pickLevel"))
		return
	end
	C2S:FireServer({ action = "practiceStart", levelKey = selectedKey })
	pracLevelKey = selectedKey
	pracStreakValue = 0
	curPracQ = nil
	curPracResult = nil
	pracFeedback.Text = ""
	lobby.Visible = false
	prac.Visible = true
	practiceLocked = true -- 最初の practiceQ が届くまでは回答を受け付けない
	renderPractice()
end)
cancelButton.MouseButton1Click:Connect(function()
	C2S:FireServer({ action = "cancelQueue" })
	setQueueing(false)
	T.status.Text = ""
end)
pracExit.MouseButton1Click:Connect(function()
	C2S:FireServer({ action = "practiceStop" })
	prac.Visible = false
	showLobby()
end)
resultOk.MouseButton1Click:Connect(function()
	result.Visible = false
	showLobby()
end)

for i, choice in ipairs(choiceButtons) do
	choice.button.MouseButton1Click:Connect(function()
		if answerLocked then
			return
		end
		answerLocked = true
		C2S:FireServer({ action = "submit", round = curRound, idx = i })
		choice.button.BackgroundColor3 = Color3.fromRGB(90, 80, 130)
	end)
end
for i, choice in ipairs(pracChoices) do
	choice.button.MouseButton1Click:Connect(function()
		if practiceLocked then
			return
		end
		practiceLocked = true
		C2S:FireServer({ action = "practiceSubmit", idx = i })
		choice.button.BackgroundColor3 = Color3.fromRGB(90, 80, 130)
	end)
end

local function setHp(fill, hp, maxHp)
	local scale = math.max(0, math.min(1, hp / maxHp))
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.new(scale, 0, 1, 0) }):Play()
end

-- ================================================================ S2C router
local function localizeArgs(args)
	if type(args) ~= "table" then
		return args
	end
	local out = {}
	for k, v in pairs(args) do
		if k == "level" and type(v) == "string" then
			out[k] = I18n.levelFull(v)
		else
			out[k] = v
		end
	end
	return out
end

S2C.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return
	end
	local a = data.action

	if a == "queue" then
		for key in pairs(levelCards) do
			queueCounts[key] = data[key] or 0
		end
		renderLevelCards()

	elseif a == "toast" then
		if data.key then
			toast(I18n.t(data.key, localizeArgs(data.args)))
		else
			toast(data.msg or "")
		end

	elseif a == "matchIntro" then
		lobby.Visible = false
		prac.Visible = false
		result.Visible = false
		battle.Visible = true
		setQueueing(false)
		T.status.Text = ""
		answerLocked = false
		curQ = nil
		curAnswer = nil
		opName.Text = "VS " .. (data.opponent or "?")
		roundLbl.Text = I18n.t("preparing")
		promptText.Text = I18n.t("title")
		promptHint.TextColor3 = COL_DIM
		promptHint.Text = data.levelKey and I18n.levelFull(data.levelKey) or ""
		suddenLbl.Visible = false
		for _, choice in ipairs(choiceButtons) do
			setChoiceText(choice, "", nil)
			choice.button.AutoButtonColor = false
		end
		hpMe, hpOp = Config.MAX_HP, Config.MAX_HP
		renderHp()
		setHp(myHp.fill, hpMe, Config.MAX_HP)
		setHp(opHp.fill, hpOp, Config.MAX_HP)
		task.wait(0.1)
		UiKit.playSound("rbxasset://sounds/bass.mp3", 0.8, 0.5)

	elseif a == "question" then
		battle.Visible = true
		prac.Visible = false
		curRound = data.round
		answerLocked = false
		practiceLocked = true
		curAnswer = nil
		curQ = {
			prompt = data.prompt,
			isKanji = data.isKanji,
			choices = data.choices,
			round = data.round,
			total = data.total,
			sudden = data.sudden,
		}
		suddenLbl.Visible = data.sudden == true
		hpMe, hpOp = data.hpMe, data.hpOp
		renderHp()
		setHp(myHp.fill, hpMe, Config.MAX_HP)
		setHp(opHp.fill, hpOp, Config.MAX_HP)
		resetChoiceColors(choiceButtons)
		renderQuestion()
		startTimer(data.timeLimit or Config.QUESTION_TIME)
		UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.6, 0.3)

	elseif a == "answerResult" then
		curAnswer = {
			correct = data.correct,
			correctIdx = data.correctIdx,
			myIdx = data.myIdx,
			dealt = data.dealt,
			taken = data.taken,
		}
		for i, choice in ipairs(choiceButtons) do
			choice.button.AutoButtonColor = false
			if i == data.correctIdx then
				choice.button.BackgroundColor3 = COL_GOOD
				choice.sub.TextColor3 = Color3.fromRGB(215, 255, 225)
			elseif i == data.myIdx and data.myIdx > 0 then
				choice.button.BackgroundColor3 = COL_BAD
				choice.sub.TextColor3 = Color3.fromRGB(255, 215, 220)
			end
		end
		if data.correct then
			UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.2, 0.6)
		else
			UiKit.playSound("rbxasset://sounds/snap.mp3", 1, 0.7)
		end
		hpMe, hpOp = data.hpMe, data.hpOp
		renderHp()
		setHp(myHp.fill, hpMe, Config.MAX_HP)
		setHp(opHp.fill, hpOp, Config.MAX_HP)
		renderQuestion()

	elseif a == "matchEnd" then
		battle.Visible = false
		result.Visible = true
		curResultData = data
		renderResult()
		UiKit.playSound("rbxasset://sounds/bass.mp3", data.win and 1.3 or 0.7, 0.6)

	elseif a == "toLobby" then
		result.Visible = false
		battle.Visible = false
		showLobby()

	elseif a == "practiceQ" then
		practiceLocked = false
		curPracResult = nil
		pracFeedback.Text = ""
		pracStreakValue = data.streak or 0
		pracLevelKey = data.levelKey or pracLevelKey
		curPracQ = {
			prompt = data.prompt,
			isKanji = data.isKanji,
			choices = data.choices,
		}
		resetChoiceColors(pracChoices)
		renderPractice()
		UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.7, 0.25)

	elseif a == "practiceResult" then
		practiceLocked = true
		curPracResult = { correct = data.correct, correctIdx = data.correctIdx }
		pracStreakValue = data.streak or 0
		for i, choice in ipairs(pracChoices) do
			choice.button.AutoButtonColor = false
			if i == data.correctIdx then
				choice.button.BackgroundColor3 = COL_GOOD
				choice.sub.TextColor3 = Color3.fromRGB(215, 255, 225)
			end
		end
		if data.correct then
			UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.2, 0.6)
		else
			UiKit.playSound("rbxasset://sounds/snap.mp3", 1, 0.7)
		end
		renderPractice()
		if not data.correct then
			task.delay(2.0, function()
				C2S:FireServer({ action = "practiceNext" })
			end)
		end
	end
end)

retranslate()
showLobby()
