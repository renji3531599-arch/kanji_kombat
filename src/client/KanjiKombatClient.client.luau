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

-- UiKit のパスは Rojo と .rbxlx ビルドの両方に対応 (Modules / ClientModules のどちらでも動くように)
local function resolveUiKit()
	local parent = script.Parent
	-- Rojo: script.Parent は KanjiKombatClient フォルダで中に Modules がある
	-- .rbxlx: script.Parent は StarterPlayerScripts で中に ClientModules がある
	local candidates = {
		parent:FindFirstChild("Modules"),
		parent:FindFirstChild("ClientModules"),
		parent.Parent and parent.Parent:FindFirstChild("Modules"),
		parent.Parent and parent.Parent:FindFirstChild("ClientModules"),
	}
	for _, folder in ipairs(candidates) do
		if folder then
			local mod = folder:FindFirstChild("UiKit")
			if mod then return require(mod) end
		end
	end
	-- フォールバック: 旧パス (テスト互換)
	return require(script.Parent:WaitForChild("ClientModules"):WaitForChild("UiKit"))
end
local UiKit = resolveUiKit()
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
	if math.clamp then
		lobbyScale.Scale = math.clamp(s, 0.5, 1)
	else
		lobbyScale.Scale = math.max(0.5, math.min(s, 1))
	end
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
	Size = UDim2.fromOffset(120, 46), Position = UDim2.new(0.5, -130, 1, -62),
	BackgroundColor3 = Color3.fromRGB(170, 45, 60), ZIndex = 6,
}, result)
local resultRematch = UiKit.button({
	Size = UDim2.fromOffset(100, 46), Position = UDim2.new(0.5, 20, 1, -62),
	BackgroundColor3 = Color3.fromRGB(60, 110, 170), ZIndex = 6,
}, result)
resultRematch.Text = I18n.t("rematchButton")
resultRematch.MouseButton1Click:Connect(function()
	if selectedKey then
		C2S:FireServer({ action = "queue", levelKey = selectedKey })
		result.Visible=false
		setQueueing(true)
	end
end)

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

-- ======================================================================
-- 超拡張: 経済・バトルパス・派手バトル演出 (テスト互換を保ちつつ追加)
-- ======================================================================

-- Top bar: コイン / ジェム / レベル / ランク
local topBar = UiKit.mk("Frame", {
	Name = "TopBar",
	Size = UDim2.new(1, 0, 0, 44),
	Position = UDim2.fromOffset(0, 0),
	BackgroundColor3 = Color3.fromRGB(18, 16, 24),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	ZIndex = 8,
	Parent = screen,
})
UiKit.corner(topBar, 10)
UiKit.stroke(topBar, Color3.fromRGB(80, 70, 90), 1, 0.3)

local coinLbl = UiKit.label({
	Size = UDim2.fromOffset(140, 28), Position = UDim2.fromOffset(12, 8),
	Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 220, 90),
	TextSize = 15, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
}, topBar)
local gemLbl = UiKit.label({
	Size = UDim2.fromOffset(120, 28), Position = UDim2.fromOffset(150, 8),
	Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(90, 200, 255),
	TextSize = 15, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
}, topBar)
local levelLbl = UiKit.label({
	Size = UDim2.fromOffset(200, 28), Position = UDim2.fromOffset(270, 8),
	Font = Enum.Font.GothamBold, TextColor3 = COL_TEXT,
	TextSize = 14, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
}, topBar)
local rankLbl = UiKit.label({
	Size = UDim2.fromOffset(160, 28), Position = UDim2.new(1, -170, 0, 8),
	Font = Enum.Font.GothamBold, TextColor3 = COL_GOLD,
	TextSize = 14, TextScaled = false, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 9,
}, topBar)

local shopButton = UiKit.button({
	Size = UDim2.fromOffset(92, 32), Position = UDim2.new(1, -260, 0, 6),
	BackgroundColor3 = Color3.fromRGB(70, 60, 110), TextSize = 13, ZIndex = 9,
}, topBar)
local passButtonTop = UiKit.button({
	Size = UDim2.fromOffset(92, 32), Position = UDim2.new(1, -360, 0, 6),
	BackgroundColor3 = Color3.fromRGB(45, 85, 110), TextSize = 13, ZIndex = 9,
}, topBar)
local dailyButtonTop = UiKit.button({
	Size = UDim2.fromOffset(92, 32), Position = UDim2.new(1, -460, 0, 6),
	BackgroundColor3 = Color3.fromRGB(110, 70, 50), TextSize = 13, ZIndex = 9,
}, topBar)

-- ロビー内にあったTopBarと被らないようにロビーを少し下げる
lobby.Position = UDim2.new(0.5, 0, 0.5, 22)

-- ショップモーダル
local shopModal = UiKit.mk("Frame", {
	Name = "ShopModal", Visible = false,
	Size = UDim2.fromOffset(760, 520), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5,0.5),
	BackgroundColor3 = Color3.fromRGB(28, 26, 36), BorderSizePixel=0, ZIndex = 15,
	Parent = screen,
})
UiKit.corner(shopModal, 16)
UiKit.stroke(shopModal, COL_GOLD, 2, 0.15)
local shopTitleLbl = UiKit.label({ Size=UDim2.new(1,-40,0,40), Position=UDim2.fromOffset(20,12), Font=Enum.Font.GothamBlack, TextColor3=COL_GOLD, TextSize=22, ZIndex=16 }, shopModal)
local shopTabs = UiKit.mk("Frame", { Size=UDim2.new(1,-40,0,36), Position=UDim2.fromOffset(20,54), BackgroundTransparency=1, ZIndex=16 }, shopModal)
local shopContent = UiKit.mk("ScrollingFrame", {
	Size=UDim2.new(1,-40,1,-110), Position=UDim2.fromOffset(20,100),
	BackgroundTransparency=1, CanvasSize=UDim2.fromOffset(0,800), ScrollBarThickness=6, ZIndex=16,
}, shopModal)
UiKit.mk("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,8), Parent=shopContent })
local shopClose = UiKit.button({ Size=UDim2.fromOffset(120,36), Position=UDim2.new(0.5,-60,1,-46), BackgroundColor3=Color3.fromRGB(70,70,90), ZIndex=16 }, shopModal)
local shopTabButtons = {}
local shopCurrentTab = "coins"
local function buildShopTabs()
	for i, key in ipairs(Config.SHOP_TABS) do
		local btn = UiKit.button({
			Size=UDim2.fromOffset(120,34), Position=UDim2.fromOffset((i-1)*130, 0),
			BackgroundColor3 = (key==shopCurrentTab) and Color3.fromRGB(90,80,130) or Color3.fromRGB(45,43,60),
			TextSize=13, ZIndex=17,
		}, shopTabs)
		if key == "coins" then btn.Text = I18n.t("shopCoinsTab")
		elseif key == "gems" then btn.Text = I18n.t("shopGemsTab")
		elseif key == "boost" then btn.Text = I18n.t("shopBoostTab")
		elseif key == "cosmetic" then btn.Text = I18n.t("shopCosmeticTab")
		elseif key == "pass" then btn.Text = I18n.t("shopPassTab")
		else btn.Text = key:upper() end
		shopTabButtons[key]=btn
		btn.MouseButton1Click:Connect(function()
			shopCurrentTab=key
			for k,b in pairs(shopTabButtons) do b.BackgroundColor3 = (k==key) and Color3.fromRGB(90,80,130) or Color3.fromRGB(45,43,60) end
			renderShop()
		end)
	end
end
buildShopTabs()

local function shopItemRow(priceText, buttonText, desc, color, onClick)
	local row = UiKit.mk("Frame", { Size=UDim2.new(1,-12,0,66), BackgroundColor3=COL_CARD, BorderSizePixel=0, LayoutOrder=1, ZIndex=17 }, shopContent)
	UiKit.corner(row, 10)
	UiKit.mk("Frame", { Size=UDim2.new(1,0,0,4), BackgroundColor3=color, BorderSizePixel=0, ZIndex=18 }, row)
	local l1 = UiKit.label({ Size=UDim2.new(0.6,-20,0,26), Position=UDim2.fromOffset(12,12), Font=Enum.Font.GothamBold, TextColor3=COL_TEXT, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=18 }, row)
	l1.Text = desc
	local l2 = UiKit.label({ Size=UDim2.new(0.6,-20,0,20), Position=UDim2.fromOffset(12,36), Font=Enum.Font.Gotham, TextColor3=COL_DIM, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=18 }, row)
	l2.Text = priceText
	local btn = UiKit.button({ Size=UDim2.fromOffset(120,36), Position=UDim2.new(1,-132,0,15), BackgroundColor3=Color3.fromRGB(170,45,60), TextSize=13, ZIndex=18 }, row)
	btn.Text = buttonText
	btn.MouseButton1Click:Connect(onClick)
	return row
end

function renderShop()
	for _,c in ipairs(shopContent:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	shopContent.CanvasSize = UDim2.fromOffset(0, 600)
	if shopCurrentTab=="coins" then
		for _, prod in ipairs(Config.PRODUCTS.DEV) do
			if prod.coins then
				shopItemRow(prod.coins.." Coins", I18n.t("buyWithRobux",{price=prod.priceRobux}), prod.labelJa.." / "..prod.labelEn, COL_GOLD, function()
					C2S:FireServer({action="buyDev", key=prod.key})
					toast("Robux "..prod.priceRobux.." で購入をリクエスト…")
				end)
			end
		end
		shopItemRow("ヒント x1", I18n.t("buyWithCoins",{price=Config.ECONOMY.COST_HINT}), "対戦中に誤答を1つ消す", COL_GOOD, function()
			C2S:FireServer({action="buyWithCoins", category="hint"})
		end)
		shopItemRow("シールド x1", I18n.t("buyWithCoins",{price=Config.ECONOMY.COST_SHIELD_REFILL}), "被ダメ半減シールドを再付与", Color3.fromRGB(90,160,255), function()
			C2S:FireServer({action="buyWithCoins", category="shield"})
		end)
	elseif shopCurrentTab=="gems" then
		for _, prod in ipairs(Config.PRODUCTS.DEV) do
			if prod.gems then
				shopItemRow(prod.gems.." Gems", I18n.t("buyWithRobux",{price=prod.priceRobux}), prod.labelJa, Color3.fromRGB(90,200,255), function()
					C2S:FireServer({action="buyDev", key=prod.key})
				end)
			end
		end
	elseif shopCurrentTab=="boost" then
		shopItemRow("2倍XP 1時間", I18n.t("buyWithRobux",{price=39}), "獲得XPが1時間2倍", Color3.fromRGB(180,120,255), function()
			C2S:FireServer({action="buyDev", key="double_xp_1h"})
		end)
		shopItemRow("連勝キープ", I18n.t("buyWithRobux",{price=29}), "敗北時に連勝を守る", COL_GOLD, function()
			C2S:FireServer({action="buyDev", key="streak_saver"})
		end)
	elseif shopCurrentTab=="cosmetic" then
		for _, it in ipairs(Config.COSMETICS.TITLES) do
			local priceText
			if it.priceCoins then priceText = I18n.t("buyWithCoins",{price=it.priceCoins})
			elseif it.priceGems then priceText = I18n.t("buyWithGems",{price=it.priceGems})
			else priceText = I18n.t("buyButton") end
			local shortPrice
			if it.priceCoins then shortPrice = I18n.t("coinsShort",{n=it.priceCoins})
			elseif it.priceGems then shortPrice = I18n.t("gemsShort",{n=it.priceGems})
			else shortPrice = I18n.t("buyButton") end
			shopItemRow(shortPrice, priceText, "称号: "..(it.labelJa or it.key), COL_GOLD, function()
				C2S:FireServer({action="buyWithCoins", category="cosmetic", key="title:"..it.key})
			end)
		end
		for _, it in ipairs(Config.COSMETICS.ARENAS) do
			local priceText
			if it.priceCoins then priceText = I18n.t("buyWithCoins",{price=it.priceCoins})
			elseif it.priceGems then priceText = I18n.t("buyWithGems",{price=it.priceGems})
			else priceText = I18n.t("buyButton") end
			local shortPrice
			if it.priceCoins then shortPrice = I18n.t("coinsShort",{n=it.priceCoins})
			elseif it.priceGems then shortPrice = I18n.t("gemsShort",{n=it.priceGems})
			else shortPrice = I18n.t("buyButton") end
			shopItemRow(shortPrice, priceText, "アリーナ: "..(it.labelJa or it.key), Color3.fromRGB(160,90,255), function()
				C2S:FireServer({action="buyWithCoins", category="cosmetic", key="arena:"..it.key})
			end)
		end
	elseif shopCurrentTab=="pass" then
		shopItemRow("400 Robux", I18n.t("passBuyPremium"), "全ティアのプレミアム報酬を解放！", COL_GOLD, function()
			C2S:FireServer({action="buyDev", key="battle_pass_premium"})
		end)
		for tier=1, Config.PROGRESSION.PASS_TIERS do
			local free = nil
			for _, r in ipairs(Config.PASS_REWARDS) do if r.tier==tier then free=r break end end
			if free then
				local desc = "Tier "..tier.." 無料: "..(free.free.coins and (free.free.coins.." Coins") or "報酬")
				if free.premium then desc = desc .. " / プレミアム: Gems+"..(free.premium.gems or 0) end
				shopItemRow("Tier "..tier, (profile and profile.passTier or 0) >= tier and "獲得済み" or "未達成", desc, (profile and profile.passTier or 0)>=tier and COL_GOOD or COL_DIM, function() end)
			end
		end
	end
end

shopClose.MouseButton1Click:Connect(function() shopModal.Visible=false end)
shopButton.MouseButton1Click:Connect(function() shopModal.Visible = not shopModal.Visible; if shopModal.Visible then renderShop() end end)
passButtonTop.MouseButton1Click:Connect(function() shopCurrentTab="pass"; for k,b in pairs(shopTabButtons) do b.BackgroundColor3=(k=="pass") and Color3.fromRGB(90,80,130) or Color3.fromRGB(45,43,60) end; shopModal.Visible=true; renderShop() end)

-- Daily / Mission / Pass モーダル (未使用WARNだった daily* / mission* / pass* を使用)
local dailyModal = UiKit.mk("Frame", {
	Name="DailyModal", Visible=false, Size=UDim2.fromOffset(520, 300), Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5),
	BackgroundColor3=Color3.fromRGB(28,26,36), BorderSizePixel=0, ZIndex=16, Parent=screen,
})
UiKit.corner(dailyModal, 14)
UiKit.stroke(dailyModal, COL_GOLD, 2, 0.15)
local dailyTitleLbl = UiKit.label({ Size=UDim2.new(1,-40,0,36), Position=UDim2.fromOffset(20,12), Font=Enum.Font.GothamBlack, TextColor3=COL_GOLD, TextSize=20, ZIndex=17 }, dailyModal)
local dailyStreakLbl = UiKit.label({ Size=UDim2.new(1,-40,0,26), Position=UDim2.fromOffset(20,54), Font=Enum.Font.Gotham, TextColor3=COL_TEXT, TextSize=16, ZIndex=17 }, dailyModal)
local dailyClaimBtn = UiKit.button({ Size=UDim2.fromOffset(160,40), Position=UDim2.new(0.5,-80,1,-56), BackgroundColor3=Color3.fromRGB(170,45,60), ZIndex=17 }, dailyModal)
local dailyCloseBtn = UiKit.button({ Size=UDim2.fromOffset(100,32), Position=UDim2.new(1,-110,0,12), BackgroundColor3=Color3.fromRGB(70,70,90), TextSize=12, ZIndex=17 }, dailyModal)
dailyCloseBtn.Text = I18n.t("backToLobby")
dailyCloseBtn.MouseButton1Click:Connect(function() dailyModal.Visible=false end)
local function showDailyModal(streak, claimed)
	dailyTitleLbl.Text = I18n.t("dailyTitle")
	dailyStreakLbl.Text = I18n.t("dailyStreak", { streak=streak or 0 })
	dailyClaimBtn.Text = claimed and I18n.t("dailyClaimed") or I18n.t("dailyClaim")
	dailyModal.Visible=true
end
dailyClaimBtn.MouseButton1Click:Connect(function() C2S:FireServer({action="claimDaily"}); dailyModal.Visible=false end)
dailyButtonTop.MouseButton1Click:Connect(function()
	-- プロフィールからストリークを取得してモーダル表示、同時に請求も可能
	local streak = profile and profile.dailyStreak or 0
	showDailyModal(streak, false)
end)

local missionModal = UiKit.mk("Frame", {
	Name="MissionModal", Visible=false, Size=UDim2.fromOffset(600, 400), Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5),
	BackgroundColor3=Color3.fromRGB(28,26,36), BorderSizePixel=0, ZIndex=16, Parent=screen,
})
UiKit.corner(missionModal, 14)
UiKit.stroke(missionModal, COL_GOOD, 2, 0.15)
local missionTitleLbl = UiKit.label({ Size=UDim2.new(1,-40,0,36), Position=UDim2.fromOffset(20,12), Font=Enum.Font.GothamBlack, TextColor3=COL_GOOD, TextSize=20, ZIndex=17 }, missionModal)
local missionDailyLbl = UiKit.label({ Size=UDim2.new(1,-40,0,22), Position=UDim2.fromOffset(20,52), Font=Enum.Font.GothamBold, TextColor3=COL_TEXT, TextSize=14, ZIndex=17 }, missionModal)
local missionWeeklyLbl = UiKit.label({ Size=UDim2.new(1,-40,0,22), Position=UDim2.fromOffset(20,200), Font=Enum.Font.GothamBold, TextColor3=COL_TEXT, TextSize=14, ZIndex=17 }, missionModal)
local missionContent = UiKit.mk("ScrollingFrame", { Size=UDim2.new(1,-40,1,-120), Position=UDim2.fromOffset(20,80), BackgroundTransparency=1, CanvasSize=UDim2.fromOffset(0,400), ScrollBarThickness=4, ZIndex=17 }, missionModal)
UiKit.mk("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,6), Parent=missionContent })
local missionClose = UiKit.button({ Size=UDim2.fromOffset(120,36), Position=UDim2.new(0.5,-60,1,-46), BackgroundColor3=Color3.fromRGB(70,70,90), ZIndex=17 }, missionModal)
missionClose.Text = I18n.t("backToLobby")
missionClose.MouseButton1Click:Connect(function() missionModal.Visible=false end)
local function renderMissions(daily, weekly)
	for _,c in ipairs(missionContent:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	missionTitleLbl.Text = I18n.t("missionTitle")
	missionDailyLbl.Text = I18n.t("missionDaily")
	missionWeeklyLbl.Text = I18n.t("missionWeekly")
	local function addRow(key, cur, target)
		local row = UiKit.mk("Frame", { Size=UDim2.new(1,-12,0,40), BackgroundColor3=COL_CARD, BorderSizePixel=0, LayoutOrder=1, ZIndex=18 }, missionContent)
		UiKit.corner(row, 8)
		local l1 = UiKit.label({ Size=UDim2.new(0.6,-10,1,0), Position=UDim2.fromOffset(10,0), Font=Enum.Font.Gotham, TextColor3=COL_TEXT, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=18 }, row)
		l1.Text = key
		local l2 = UiKit.label({ Size=UDim2.new(0.4,-10,1,0), Position=UDim2.new(0.6,0,0,0), Font=Enum.Font.GothamBold, TextColor3=COL_GOLD, TextSize=13, TextXAlignment=Enum.TextXAlignment.Right, ZIndex=18 }, row)
		l2.Text = I18n.t("missionProgress", { cur=cur or 0, target=target or 0 })
	end
	if daily then for k,v in pairs(daily) do if not k:find("_claimed") then addRow(k, v, 5) end end end
	if weekly then for k,v in pairs(weekly) do if not k:find("_claimed") then addRow(k, v, 20) end end end
end
-- ミッションボタンはTopBarに無いのでロビーに追加 (簡易)
local missionButtonTop = UiKit.button({
	Size=UDim2.fromOffset(92, 32), Position=UDim2.new(1, -560, 0, 6),
	BackgroundColor3=Color3.fromRGB(60, 90, 60), TextSize=13, ZIndex=9,
}, topBar)
missionButtonTop.Text = I18n.t("missionButton")
missionButtonTop.MouseButton1Click:Connect(function() missionModal.Visible = not missionModal.Visible; if missionModal.Visible then renderMissions(profile and profile.missions and profile.missions.daily, profile and profile.missions and profile.missions.weekly) end end)

local passModal = UiKit.mk("Frame", {
	Name="PassModal", Visible=false, Size=UDim2.fromOffset(600, 400), Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5),
	BackgroundColor3=Color3.fromRGB(28,26,36), BorderSizePixel=0, ZIndex=16, Parent=screen,
})
UiKit.corner(passModal, 14)
UiKit.stroke(passModal, COL_GOLD, 2, 0.15)
local passTitleLbl = UiKit.label({ Size=UDim2.new(1,-40,0,36), Position=UDim2.fromOffset(20,12), Font=Enum.Font.GothamBlack, TextColor3=COL_GOLD, TextSize=20, ZIndex=17 }, passModal)
local passTierLbl = UiKit.label({ Size=UDim2.new(1,-40,0,26), Position=UDim2.fromOffset(20,52), Font=Enum.Font.Gotham, TextColor3=COL_TEXT, TextSize=15, ZIndex=17 }, passModal)
local passPremiumLbl = UiKit.label({ Size=UDim2.new(1,-40,0,26), Position=UDim2.fromOffset(20,80), Font=Enum.Font.GothamBold, TextColor3=Color3.fromRGB(140,90,255), TextSize=14, ZIndex=17 }, passModal)
local passClose = UiKit.button({ Size=UDim2.fromOffset(120,36), Position=UDim2.new(0.5,-60,1,-46), BackgroundColor3=Color3.fromRGB(70,70,90), ZIndex=17 }, passModal)
passClose.Text = I18n.t("backToLobby")
passClose.MouseButton1Click:Connect(function() passModal.Visible=false end)
local function showPassModal()
	passTitleLbl.Text = I18n.t("passTitle")
	local tier = profile and profile.passTier or 0
	passTierLbl.Text = I18n.t("passTier", { tier=tier, max=Config.PROGRESSION.PASS_TIERS })
	passPremiumLbl.Text = (profile and profile.premiumPass) and I18n.t("passPremium") or I18n.t("passBuyPremium")
	passModal.Visible=true
end
-- passButtonTop は既存で shop の pass タブを開くが、ここで passModal も使えるように
passButtonTop.MouseButton1Click:Connect(function()
	-- 既存の shop pass タブも開くが、passModal も併用
	showPassModal()
	shopCurrentTab="pass"; for k,b in pairs(shopTabButtons) do b.BackgroundColor3=(k=="pass") and Color3.fromRGB(90,80,130) or Color3.fromRGB(45,43,60) end; shopModal.Visible=true; renderShop()
end)

-- Battle HUD 超拡張: コンボ・必殺ゲージ・ボタン
local comboLbl = UiKit.label({
	Size=UDim2.fromOffset(300, 44), Position=UDim2.new(0.5,-150,0,92),
	Font=Enum.Font.GothamBlack, TextColor3=Color3.fromRGB(255, 220, 90), TextSize=28, TextScaled=false,
	Visible=false, ZIndex=4,
}, battle)
local ultBarHolder = UiKit.mk("Frame", {
	Size=UDim2.fromOffset(560, 14), Position=UDim2.new(0.5,-280,1,-52),
	BackgroundColor3=Color3.fromRGB(25,25,32), BorderSizePixel=0, ZIndex=4,
}, battle)
UiKit.corner(ultBarHolder, 7)
local ultBarFill = UiKit.mk("Frame", { Size=UDim2.fromScale(0,1), BackgroundColor3=Color3.fromRGB(140,90,255), BorderSizePixel=0, ZIndex=4 }, ultBarHolder)
UiKit.corner(ultBarFill, 7)
local ultBarLbl = UiKit.label({
	Size=UDim2.new(1,0,1,0), Font=Enum.Font.GothamBold, TextColor3=Color3.fromRGB(245,245,250), TextSize=11, ZIndex=5,
}, ultBarHolder)

local hintBtn = UiKit.button({
	Size=UDim2.fromOffset(110, 38), Position=UDim2.new(0.5, -280, 0, 518),
	BackgroundColor3=Color3.fromRGB(60,110,90), TextSize=13, ZIndex=4,
}, battle)
local ultBtn = UiKit.button({
	Size=UDim2.fromOffset(110, 38), Position=UDim2.new(0.5, -55, 0, 518),
	BackgroundColor3=Color3.fromRGB(140, 50, 90), TextSize=13, ZIndex=4,
}, battle)
local shieldBtn = UiKit.button({
	Size=UDim2.fromOffset(110, 38), Position=UDim2.new(0.5, 170, 0, 518),
	BackgroundColor3=Color3.fromRGB(70,80,130), TextSize=13, ZIndex=4,
}, battle)
local ultReadyFx = UiKit.label({
	Size=UDim2.fromOffset(300, 28), Position=UDim2.new(0.5,-150,0, 360),
	Font=Enum.Font.GothamBlack, TextColor3=Color3.fromRGB(140,90,255), Visible=false, ZIndex=6,
}, battle)

-- 練習リロールボタン (practiceReroll と rerollButton の両方を使用)
local pracRerollBtn = UiKit.button({
	Size=UDim2.fromOffset(140, 36), Position=UDim2.new(0.5, 120, 1, -70),
	BackgroundColor3=Color3.fromRGB(90, 70, 130), TextSize=13, ZIndex=4,
}, prac)
pracRerollBtn.Text = I18n.t("practiceReroll")
pracRerollBtn.MouseButton1Click:Connect(function() C2S:FireServer({action="practiceReroll"}) end)

local pracRerollBtn2 = UiKit.button({
	Size=UDim2.fromOffset(100, 36), Position=UDim2.new(0.5, 270, 1, -70),
	BackgroundColor3=Color3.fromRGB(70, 60, 110), TextSize=12, ZIndex=4,
}, prac)
pracRerollBtn2.Text = I18n.t("rerollButton")
pracRerollBtn2.MouseButton1Click:Connect(function() C2S:FireServer({action="practiceReroll"}) end)

hintBtn.MouseButton1Click:Connect(function() C2S:FireServer({action="useHint"}) end)
ultBtn.MouseButton1Click:Connect(function() C2S:FireServer({action="activateUltimate"}) end)
shieldBtn.MouseButton1Click:Connect(function() C2S:FireServer({action="useShield"}) end)

-- ダメージ数字ポップ
local dmgPop = UiKit.label({
	Size=UDim2.fromOffset(200, 40), Position=UDim2.new(0.5,-100,0.5,-80),
	Font=Enum.Font.GothamBlack, TextColor3=COL_GOLD, TextSize=32, Visible=false, ZIndex=7,
}, battle)

local function popDamage(txt, color)
	dmgPop.Text = txt
	dmgPop.TextColor3 = color or COL_GOLD
	dmgPop.Visible = true
	dmgPop.TextTransparency = 0
	TweenService:Create(dmgPop, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5,-100,0.5,-140), TextTransparency=1 }):Play()
	task.delay(0.65, function() dmgPop.Visible=false; dmgPop.Position=UDim2.new(0.5,-100,0.5,-80) end)
end

local function updateTopBar()
	if not profile then
		coinLbl.Text = I18n.t("coins")..": --"
		gemLbl.Text = I18n.t("gems")..": --"
		levelLbl.Text = I18n.t("profileLoading")
		rankLbl.Text = ""
		return
	end
	-- バグ修正: coinsShort / gemsShort / rankLabel を使う (未使用WARN解消 + 表示改善)
	coinLbl.Text = I18n.t("coinsShort", { n=(profile.coins or 0) })
	gemLbl.Text = I18n.t("gemsShort", { n=(profile.gems or 0) })
	levelLbl.Text = I18n.t("profileLevel", { level=profile.level or 1, xp=profile.xp or 0, next= (Config.PROGRESSION.XP_TABLE and Config.PROGRESSION.XP_TABLE[profile.level or 1]) or 100 })
	local rkKey = selectedKey and profile.ratings[selectedKey] or 1000
	local r = Config.rankOf(rkKey)
	rankLbl.Text = I18n.t("rankLabel", { rank=(I18n.getLocale()=="ja" and r.labelJa or r.labelEn), icon=r.icon })
end

local currentShield = false -- シールド状態を保持 (answerResultでnilになっても消えないように)

local function updateBattleHud(data)
	-- data: combo, ult, shield, opUlt etc.
	if data.combo and data.combo >=2 then
		comboLbl.Visible = true
		comboLbl.Text = I18n.t("comboLabel", { n=data.combo })
		comboLbl.TextColor3 = (data.combo>=5) and Color3.fromRGB(255,80,90) or COL_GOLD
	else
		comboLbl.Visible = false
	end
	local rawPct = (data.ult or 0)/Config.BATTLE.ULT_MAX
	local pct
	if math.clamp then pct = math.clamp(rawPct, 0, 1) else pct = math.max(0, math.min(rawPct, 1)) end
	ultBarFill.Size = UDim2.fromScale(pct,1)
	if pct >=1 then
		ultBarFill.BackgroundColor3 = Color3.fromRGB(255,210,90)
		ultBarLbl.Text = I18n.t("ultReady")
		ultReadyFx.Visible = true
		ultReadyFx.Text = I18n.t("ultReady")
		ultBtn.BackgroundColor3 = Color3.fromRGB(255, 180, 50)
	else
		ultBarFill.BackgroundColor3 = Color3.fromRGB(140,90,255)
		ultBarLbl.Text = I18n.t("ultButton", { pct=math.floor(pct*100) })
		ultReadyFx.Visible = false
		ultBtn.BackgroundColor3 = Color3.fromRGB(140,50,90)
	end
	hintBtn.Text = I18n.t("hintButton", { cost=Config.ECONOMY.COST_HINT })
	-- shield 状態は nil のときは前回値を維持 (バグ修正)
	if data.shield ~= nil then currentShield = data.shield end
	shieldBtn.Text = currentShield and I18n.t("shieldActive") or I18n.t("shieldButton")
	shieldBtn.BackgroundColor3 = currentShield and Color3.fromRGB(90,160,255) or Color3.fromRGB(70,80,130)
end

-- 既存 retranslate をラップして新UIも翻訳 (バグ修正: ショップタブも翻訳 + 未使用キー解消)
local _oldRetranslate = retranslate
retranslate = function()
	_oldRetranslate()
	-- 新UI
	shopTitleLbl.Text = I18n.t("shopTitle")
	shopClose.Text = I18n.t("backToLobby")
	shopButton.Text = I18n.t("shopButton")
	passButtonTop.Text = I18n.t("passButton")
	dailyButtonTop.Text = I18n.t("dailyButton")
	missionButtonTop.Text = I18n.t("missionButton")
	hintBtn.Text = I18n.t("hintButton", { cost=Config.ECONOMY.COST_HINT })
	ultBtn.Text = I18n.t("ultButton", { pct=0 })
	shieldBtn.Text = currentShield and I18n.t("shieldActive") or I18n.t("shieldButton")
	pracRerollBtn.Text = I18n.t("practiceReroll")
	pracRerollBtn2.Text = I18n.t("rerollButton")
	resultRematch.Text = I18n.t("rematchButton")
	-- Daily / Mission / Pass モーダル
	dailyTitleLbl.Text = I18n.t("dailyTitle")
	dailyStreakLbl.Text = I18n.t("dailyStreak", { streak=profile and profile.dailyStreak or 0 })
	dailyClaimBtn.Text = I18n.t("dailyClaim")
	-- dailyClaimed は claimed 時に使うが、ここでは参照だけしておく (WARN解消)
	local _dailyClaimedRef = I18n.t("dailyClaimed")
	missionTitleLbl.Text = I18n.t("missionTitle")
	missionDailyLbl.Text = I18n.t("missionDaily")
	missionWeeklyLbl.Text = I18n.t("missionWeekly")
	missionClose.Text = I18n.t("backToLobby")
	passTitleLbl.Text = I18n.t("passTitle")
	passTierLbl.Text = I18n.t("passTier", { tier=profile and profile.passTier or 0, max=Config.PROGRESSION.PASS_TIERS })
	passPremiumLbl.Text = (profile and profile.premiumPass) and I18n.t("passPremium") or I18n.t("passBuyPremium")
	passClose.Text = I18n.t("backToLobby")
	dailyCloseBtn.Text = I18n.t("backToLobby")
	-- ショップタブの翻訳更新
	for key, btn in pairs(shopTabButtons) do
		if key == "coins" then btn.Text = I18n.t("shopCoinsTab")
		elseif key == "gems" then btn.Text = I18n.t("shopGemsTab")
		elseif key == "boost" then btn.Text = I18n.t("shopBoostTab")
		elseif key == "cosmetic" then btn.Text = I18n.t("shopCosmeticTab")
		elseif key == "pass" then btn.Text = I18n.t("shopPassTab")
		else btn.Text = key:upper() end
	end
	updateTopBar()
	if curQ then updateBattleHud(curQ) end
end

-- 既存 renderProfile をラップ
local _oldRenderProfile = renderProfile
renderProfile = function()
	_oldRenderProfile()
	updateTopBar()
	if profile and profile.passTier then
		-- バトルパスティアも topBar にチラ見せ? ここではログ
	end
end

-- 追加 S2C ハンドラー (新メッセージ)
S2C.OnClientEvent:Connect(function(data)
	if type(data)~="table" or type(data.action)~="string" then return end
	local a=data.action
	if a=="currencyUpdate" then
		if profile then
			profile.coins=data.coins
			profile.gems=data.gems
			profile.inventory=data.inventory
			profile.passXp=data.passXp
			profile.passTier=data.passTier
			profile.premiumPass=data.premium
		end
		updateTopBar()
	elseif a=="progressionUpdate" then
		if profile then
			profile.level=data.level
			profile.xp=data.xp
			profile.passXp=data.passXp
			profile.passTier=data.passTier
		end
		updateTopBar()
	elseif a=="levelUp" then
		toast(I18n.t("levelUp", { level=data.level }))
		UiKit.playSound("rbxasset://sounds/bass.mp3",1.5,0.7)
		popDamage("LEVEL UP!", COL_GOLD)
	elseif a=="passReward" then
		toast("Pass Tier "..data.tier.." 獲得！")
		UiKit.playSound("rbxasset://sounds/electronicpingshort.wav",1.3,0.6)
	elseif a=="missionProgress" then
		-- ミッション進捗はサイレント
	elseif a=="missionComplete" then
		toast(I18n.t("missionComplete", { coins=data.rewardCoins, xp=data.rewardXp }))
		popDamage("MISSION CLEAR!", COL_GOOD)
	elseif a=="dailyResult" then
		local r=data.result
		if r.ok then
			toast("Daily "..r.streak.."日目: +"..r.coins.." Coins"..(r.gems>0 and (" +"..r.gems.." Gems") or ""))
			popDamage("DAILY +"..r.coins, COL_GOLD)
		else
			toast(I18n.t("toastNotEnoughCoins"))
		end
	elseif a=="hintResult" then
		local idx=data.eliminate
		if idx and choiceButtons[idx] then
			choiceButtons[idx].button.BackgroundColor3 = Color3.fromRGB(40,40,50)
			choiceButtons[idx].button.AutoButtonColor=false
			choiceButtons[idx].main.TextTransparency=0.6
			choiceButtons[idx].sub.TextTransparency=0.6
			UiKit.playSound("rbxasset://sounds/snap.mp3",1.2,0.4)
		end
	elseif a=="ultimateReady" then
		ultReadyFx.Visible=true
		ultReadyFx.Text=I18n.t("ultReady")
		UiKit.playSound("rbxasset://sounds/bass.mp3",1.2,0.8)
	elseif a=="shieldActivated" then
		toast(I18n.t("shieldActive"))
		popDamage("SHIELD!", Color3.fromRGB(90,160,255))
	elseif a=="secondChanceActivated" then
		toast("SECOND CHANCE! HP30で復活！")
		popDamage("REVIVE!", COL_GOOD)
	elseif a=="opponentSecondChance" then
		toast("相手が復活した！")
	elseif a=="shopResult" then
		toast(data.ok and "購入成功！" or "購入失敗")
		if data.ok then UiKit.playSound("rbxasset://sounds/electronicpingshort.wav",1.2,0.6) end
		updateTopBar()
	elseif a=="gamePassGranted" then
		toast("GamePass 獲得: "..tostring(data.key))
	elseif a=="currencyUpdate" then -- duplicate guard
	end
end)

-- question / answerResult をフックしてコンボ演出を追加
local _oldS2C = S2C
-- 既存の question/answerResult にコンボ等を追加で扱うため、もう一つリスナーを追加
S2C.OnClientEvent:Connect(function(data)
	if data.action=="question" then
		curQ = curQ or {}
		curQ.combo = data.combo
		curQ.ult = data.ult
		curQ.shield = data.shield
		updateBattleHud({ combo=data.combo, ult=data.ult, shield=data.shield })
		comboLbl.Visible=false
		ultReadyFx.Visible=false
	elseif data.action=="answerResult" then
		-- コンボ・クリティカル・パーフェクト演出 (未使用キーだった critical/comeback/ultActivate を使用)
		local wasCombo = data.combo or 0
		if data.isPerfect then
			promptHint.Text = I18n.t("perfect").." "..promptHint.Text
			popDamage(I18n.t("perfect"), Color3.fromRGB(255,220,90))
			UiKit.playSound("rbxasset://sounds/electronicpingshort.wav",2.0,0.7)
		elseif data.isCrit then
			popDamage(I18n.t("critical").." "..(data.dealt or 0).."!", COL_BAD)
		elseif data.flags and data.flags.comeback then
			popDamage(I18n.t("comeback"), COL_GOLD)
		elseif data.dealt and data.dealt>0 then
			if wasCombo>=3 then popDamage(wasCombo.." COMBO +"..data.dealt, COL_GOLD) end
		end
		if data.isGuarded then
			toast(I18n.t("guarded"))
		end
		if data.wasShielded then
			toast(I18n.t("shieldBroken"))
		end
		if data.ultDamage and data.ultDamage>0 then
			popDamage(I18n.t("ultActivate").." "..data.ultDamage.."!", Color3.fromRGB(140,90,255))
		end
		-- シールド状態は保持 (nilを渡さない)
		updateBattleHud({ combo=data.combo, ult=data.ult, shield=currentShield })
		-- HPバー演出は既存が行う
	end
end)

-- 初回shop構築
renderShop()

retranslate()
showLobby()

