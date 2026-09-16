--!nonstrict
-- 漢字コンバット クライアント
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent:WaitForChild("ClientModules"):WaitForChild("UiKit"))
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

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

local screen = UiKit.mk("ScreenGui", {
	Name = "KanjiKombatUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

-- ================================================================ lobby
local lobby = UiKit.mk("Frame", {
	Name = "Lobby",
	Size = UDim2.fromOffset(860, 620),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COL_BG,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
}, screen)
UiKit.corner(lobby, 18)
UiKit.stroke(lobby, Color3.fromRGB(120, 60, 70), 2, 0.15)

UiKit.label({
	Size = UDim2.new(1, -40, 0, 56), Position = UDim2.fromOffset(20, 12),
	Font = Enum.Font.GothamBold, Text = "漢字コンバット", TextColor3 = COL_GOLD,
}, lobby)
UiKit.label({
	Size = UDim2.new(1, -40, 0, 22), Position = UDim2.new(0, 20, 0, 64),
	Font = Enum.Font.Gotham, TextColor3 = COL_DIM, Text = "読みオンリー対戦 〜 級を選んで対戦相手と即バトル！",
}, lobby)

local profileChip = UiKit.label({
	Size = UDim2.new(0, 380, 0, 26), Position = UDim2.new(1, -400, 0, 16),
	Font = Enum.Font.Gotham, TextColor3 = COL_TEXT, TextXAlignment = Enum.TextXAlignment.Right,
	Text = "プロフィール読込中…",
}, lobby)

local statusLabel = UiKit.label({
	Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0, 20, 1, -110),
	Font = Enum.Font.Gotham, TextColor3 = COL_GOLD, Text = "",
}, lobby)

local levelCards = {} -- [key] = {frame, rating, queue}

local grid = UiKit.mk("Frame", {
	Size = UDim2.new(1, -40, 1, -210), Position = UDim2.fromOffset(20, 96),
	BackgroundTransparency = 1,
}, lobby)
UiKit.mk("UIGridLayout", {
	CellSize = UDim2.fromOffset(193, 118),
	CellPadding = UDim2.fromOffset(9, 9),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = grid,
})

local selectedKey = nil

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
		local lbl = UiKit.label({
			Size = UDim2.new(1, -12, 0, 34), Position = UDim2.fromOffset(10, 10),
			Text = lv.label, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		UiKit.label({
			Size = UDim2.new(1, -12, 0, 18), Position = UDim2.new(0, 10, 0, 44),
			Font = Enum.Font.Gotham, TextColor3 = COL_DIM, Text = lv.desc,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local ratingLbl = UiKit.label({
			Size = UDim2.new(1, -12, 0, 18), Position = UDim2.new(0, 10, 0, 64),
			Font = Enum.Font.Gotham, TextColor3 = COL_TEXT, Text = "1000",
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local queueLbl = UiKit.label({
			Size = UDim2.new(1, -12, 0, 18), Position = UDim2.new(0, 10, 0, 84),
			Font = Enum.Font.Gotham, TextColor3 = COL_GOLD, Text = "漢字 " .. lv.kanji .. "字 / 1000問",
			TextXAlignment = Enum.TextXAlignment.Left,
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
			statusLabel.Text = lv.label .. "（" .. lv.desc .. "）を選択中"
		end)
		levelCards[lv.key] = { frame = card, rating = ratingLbl, queue = queueLbl }
	end
end
buildLevelCards()

local battleButton = UiKit.button({
	Size = UDim2.fromOffset(200, 46), Position = UDim2.new(0, 20, 1, -70),
	BackgroundColor3 = Color3.fromRGB(170, 45, 60), Text = "対戦エントリー",
}, lobby)
local practiceButton = UiKit.button({
	Size = UDim2.fromOffset(140, 46), Position = UDim2.new(0, 232, 1, -70),
	BackgroundColor3 = Color3.fromRGB(60, 110, 170), Text = "練習",
}, lobby)
local cancelButton = UiKit.button({
	Size = UDim2.fromOffset(140, 46), Position = UDim2.new(0, 384, 1, -70),
	BackgroundColor3 = Color3.fromRGB(70, 70, 90), Text = "キャンセル", Visible = false,
}, lobby)

-- ================================================================ battle
local battle = UiKit.mk("Frame", {
	Name = "Battle", Visible = false, Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COL_BG, BackgroundTransparency = 0.25, BorderSizePixel = 0,
}, screen)

local opName = UiKit.label({
	Size = UDim2.fromOffset(360, 26), Position = UDim2.new(0.5, -180, 0, 18),
	Font = Enum.Font.GothamBold, Text = "対戦相手",
}, battle)
local _, opFill = UiKit.hpBar(battle, UDim2.fromOffset(560, 22), UDim2.new(0.5, -280, 0, 50), COL_BAD, Vector2.new(0, 0))
UiKit.label({ Size = UDim2.fromOffset(80, 22), Position = UDim2.new(0.5, -280, 0, 48), Font = Enum.Font.Gotham, TextColor3 = COL_DIM, Text = "相手HP", ZIndex = 3 }, battle)

local roundLbl = UiKit.label({
	Size = UDim2.fromOffset(200, 30), Position = UDim2.new(0.5, -100, 0, 86),
	Font = Enum.Font.GothamBold, TextColor3 = COL_DIM, Text = "ROUND 1/10",
}, battle)

local promptCard = UiKit.mk("Frame", {
	Size = UDim2.fromOffset(680, 190), Position = UDim2.new(0.5, -340, 0, 130),
	BackgroundColor3 = COL_CARD, BorderSizePixel = 0,
}, battle)
UiKit.corner(promptCard, 14)
UiKit.stroke(promptCard, Color3.fromRGB(120, 90, 100), 2, 0.2)
local promptText = UiKit.label({
	Size = UDim2.new(1, -30, 1, -40), Position = UDim2.fromOffset(15, 8),
	Font = Enum.Font.GothamBold, TextColor3 = COL_TEXT, Text = "",
}, promptCard)
UiKit.label({
	Name = "Hint", Size = UDim2.new(1, -30, 0, 26), Position = UDim2.new(0, 15, 1, -32),
	Font = Enum.Font.Gotham, TextColor3 = COL_DIM, Text = "読み方を選べ",
}, promptCard)

local timerHolder = UiKit.mk("Frame", {
	Size = UDim2.fromOffset(680, 12), Position = UDim2.new(0.5, -340, 0, 334),
	BackgroundColor3 = Color3.fromRGB(25, 25, 32), BorderSizePixel = 0,
}, battle)
UiKit.corner(timerHolder, 6)
local timerFill = UiKit.mk("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = COL_GOLD, BorderSizePixel = 0,
}, timerHolder)
UiKit.corner(timerFill, 6)

local choiceButtons = {}
for i = 1, 4 do
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	local b = UiKit.button({
		Size = UDim2.fromOffset(330, 66),
		Position = UDim2.new(0.5, -335 + col * 340, 0, 362 + row * 76),
		BackgroundColor3 = Color3.fromRGB(45, 43, 60),
		TextSize = 24,
	}, battle)
	choiceButtons[i] = b
end

local myHpHolder, myFill = UiKit.hpBar(battle, UDim2.fromOffset(560, 24), UDim2.new(0.5, -280, 1, -76), COL_GOOD, Vector2.new(0, 0))
local suddenLbl = UiKit.label({
	Size = UDim2.fromOffset(400, 34), Position = UDim2.new(0.5, -200, 1, -120),
	Font = Enum.Font.GothamBold, TextColor3 = COL_BAD, Text = "サドンデス！",
	Visible = false,
}, battle)

-- ================================================================ practice
local prac = UiKit.mk("Frame", {
	Name = "Practice", Visible = false, Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COL_BG, BackgroundTransparency = 0.25, BorderSizePixel = 0,
}, screen)
UiKit.label({
	Size = UDim2.fromOffset(400, 36), Position = UDim2.new(0.5, -200, 0, 24),
	Font = Enum.Font.GothamBold, TextColor3 = COL_GOLD, Text = "練習モード",
}, prac)
local pracStreak = UiKit.label({
	Size = UDim2.fromOffset(400, 28), Position = UDim2.new(0.5, -200, 0, 60),
	Font = Enum.Font.Gotham, TextColor3 = COL_TEXT, Text = "連続正解 0",
}, prac)
local pracCard = UiKit.mk("Frame", {
	Size = UDim2.fromOffset(680, 170), Position = UDim2.new(0.5, -340, 0, 120),
	BackgroundColor3 = COL_CARD, BorderSizePixel = 0,
}, prac)
UiKit.corner(pracCard, 14)
local pracText = UiKit.label({
	Size = UDim2.new(1, -30, 1, -20), Position = UDim2.fromOffset(15, 10),
	Font = Enum.Font.GothamBold, TextColor3 = COL_TEXT,
}, pracCard)
local pracChoices = {}
for i = 1, 4 do
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	local b = UiKit.button({
		Size = UDim2.fromOffset(330, 64),
		Position = UDim2.new(0.5, -335 + col * 340, 0, 310 + row * 74),
		BackgroundColor3 = Color3.fromRGB(45, 43, 60),
	}, prac)
	pracChoices[i] = b
end
local pracFeedback = UiKit.label({
	Size = UDim2.fromOffset(600, 40), Position = UDim2.new(0.5, -300, 0, 470),
	Font = Enum.Font.GothamBold, TextColor3 = COL_GOOD, Text = "",
}, prac)
local pracExit = UiKit.button({
	Size = UDim2.fromOffset(160, 44), Position = UDim2.new(0.5, -80, 1, -70),
	BackgroundColor3 = Color3.fromRGB(70, 70, 90), Text = "練習をやめる",
}, prac)

-- ================================================================ result / overlay
local result = UiKit.mk("Frame", {
	Name = "Result", Visible = false, Size = UDim2.fromOffset(460, 260),
	Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COL_CARD, BorderSizePixel = 0, ZIndex = 5,
}, screen)
UiKit.corner(result, 16)
UiKit.stroke(result, COL_GOLD, 2, 0.2)
local resultTitle = UiKit.label({
	Size = UDim2.new(1, -30, 0, 80), Position = UDim2.fromOffset(15, 20),
	Font = Enum.Font.GothamBlack, Text = "WIN！", ZIndex = 6,
}, result)
local resultDetail = UiKit.label({
	Size = UDim2.new(1, -30, 0, 70), Position = UDim2.new(0, 15, 0, 105),
	Font = Enum.Font.Gotham, TextColor3 = COL_TEXT, Text = "", ZIndex = 6,
}, result)
local resultOk = UiKit.button({
	Size = UDim2.fromOffset(180, 46), Position = UDim2.new(0.5, -90, 1, -62),
	BackgroundColor3 = Color3.fromRGB(170, 45, 60), Text = "ロビーへ", ZIndex = 6,
}, result)

local toastLbl = UiKit.label({
	Size = UDim2.fromOffset(520, 34), Position = UDim2.new(0.5, -260, 0, 120),
	Font = Enum.Font.GothamBold, TextColor3 = COL_GOLD,
	BackgroundTransparency = 1, Text = "", ZIndex = 10,
}, screen)
local toastToken = 0
local function toast(msg)
	toastToken = toastToken + 1
	local my = toastToken
	toastLbl.Text = msg
	task.delay(2.6, function()
		if toastToken == my then
			toastLbl.Text = ""
		end
	end)
end

-- ================================================================ state helpers
local profile = nil
local curRound = 0
local answerLocked = false
local practiceLocked = false
local lastPracChoices = nil
local queueing = false

local function refreshProfile()
	task.spawn(function()
		local ok, p = pcall(function()
			return GetProfileRF:InvokeServer()
		end)
		if ok and type(p) == "table" then
			profile = p
			if profile.wins then
				profileChip.Text = string.format("通算 %d勝 %d敗　連続 %d", profile.wins, profile.losses or 0, profile.streak or 0)
			end
			for key, card in pairs(levelCards) do
				local r = (profile.ratings and profile.ratings[key]) or 1000
				card.rating.Text = "レート " .. tostring(r)
			end
		end
	end)
end

local function setQueueing(v)
	queueing = v
	battleButton.Visible = not v
	practiceButton.Visible = not v
	cancelButton.Visible = v
end

local function showLobby()
	battle.Visible = false
	prac.Visible = false
	result.Visible = false
	lobby.Visible = true
	refreshProfile()
end

-- ---------------------------------------------------------- battle flow
local function setChoicesEnabled(list, enabled)
	for _, b in ipairs(list) do
		b.AutoButtonColor = enabled
		b.BackgroundColor3 = Color3.fromRGB(45, 43, 60)
	end
end

local function startTimer(seconds)
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.BackgroundColor3 = COL_GOLD
	local tween = TweenService:Create(timerFill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
	tween:Play()
end

local function showQuestion(data, choicesButtons, promptLabel)
	promptLabel.Text = data.prompt
	if data.isKanji then
		promptLabel.Text = "『" .. data.prompt .. "』"
	end
	for i, b in ipairs(choicesButtons) do
		b.Text = data.choices[i]
		b.BackgroundColor3 = Color3.fromRGB(45, 43, 60)
	end
	setChoicesEnabled(choicesButtons, true)
end

battleButton.MouseButton1Click:Connect(function()
	if not selectedKey then
		toast("級を選んでね！")
		return
	end
	C2S:FireServer({ action = "queue", levelKey = selectedKey })
	setQueueing(true)
	statusLabel.Text = "マッチング中…"
end)
practiceButton.MouseButton1Click:Connect(function()
	if not selectedKey then
		toast("級を選んでね！")
		return
	end
	C2S:FireServer({ action = "practiceStart", levelKey = selectedKey })
	lobby.Visible = false
	prac.Visible = true
	practiceLocked = false
	pracFeedback.Text = ""
end)
cancelButton.MouseButton1Click:Connect(function()
	C2S:FireServer({ action = "cancelQueue" })
	setQueueing(false)
	statusLabel.Text = ""
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

for i, b in ipairs(choiceButtons) do
	b.MouseButton1Click:Connect(function()
		if answerLocked then
			return
		end
		answerLocked = true
		C2S:FireServer({ action = "submit", round = curRound, idx = i })
		b.BackgroundColor3 = Color3.fromRGB(90, 80, 130)
	end)
end
for i, b in ipairs(pracChoices) do
	b.MouseButton1Click:Connect(function()
		if practiceLocked then
			return
		end
		practiceLocked = true
		C2S:FireServer({ action = "practiceSubmit", idx = i })
		b.BackgroundColor3 = Color3.fromRGB(90, 80, 130)
	end)
end

local function setHp(fill, hp, maxHp)
	local scale = math.max(0, math.min(1, hp / maxHp))
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.new(scale, 0, 1, 0) }):Play()
end

-- ================================================================ S2C router
S2C.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return
	end
	local a = data.action

	if a == "queue" then
		for key, card in pairs(levelCards) do
			local n = data[key] or 0
			if n > 0 then
				card.queue.Text = "対戦待ち " .. n .. "人"
			else
				local lv = Config.levelByKey(key)
				card.queue.Text = "漢字 " .. lv.kanji .. "字 / 1000問"
			end
		end

	elseif a == "toast" then
		toast(data.msg or "")

	elseif a == "matchIntro" then
		lobby.Visible = false
		prac.Visible = false
		result.Visible = false
		battle.Visible = true
		setQueueing(false)
		statusLabel.Text = ""
		answerLocked = false
		opName.Text = "VS " .. (data.opponent or "?")
		roundLbl.Text = "準備中…"
		promptText.Text = Config.GAME_NAME
		suddenLbl.Visible = false
		setChoicesEnabled(choiceButtons, false)
		for i, b in ipairs(choiceButtons) do
			b.Text = ""
		end
		task.wait(0.1)
		UiKit.playSound("rbxasset://sounds/bass.mp3", 0.8, 0.5)

	elseif a == "question" then
		battle.Visible = true
		prac.Visible = false
		curRound = data.round
		answerLocked = false
		practiceLocked = true
		roundLbl.Text = data.sudden and "サドンデス" or (("ROUND %d/%d"):format(data.round, data.total))
		suddenLbl.Visible = data.sudden == true
		showQuestion(data, choiceButtons, promptText)
		startTimer(data.timeLimit or 12)
		setHp(myFill, data.hpMe, Config.MAX_HP)
		setHp(opFill, data.hpOp, Config.MAX_HP)
		UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.6, 0.3)

	elseif a == "answerResult" then
		local myBtn = nil
		local correctBtn = nil
		for i, b in ipairs(choiceButtons) do
			b.AutoButtonColor = false
			if i == data.correctIdx then
				correctBtn = b
				b.BackgroundColor3 = COL_GOOD
			elseif i == data.myIdx and data.myIdx > 0 then
				b.BackgroundColor3 = COL_BAD
				myBtn = b
			end
		end
		if data.correct then
			UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.2, 0.6)
		else
			UiKit.playSound("rbxasset://sounds/snap.mp3", 1, 0.7)
		end
		setHp(myFill, data.hpMe, Config.MAX_HP)
		setHp(opFill, data.hpOp, Config.MAX_HP)
		task.delay(1.4, function()
			for _, b in ipairs(choiceButtons) do
				b.BackgroundColor3 = Color3.fromRGB(45, 43, 60)
			end
		end)

	elseif a == "matchEnd" then
		battle.Visible = false
		result.Visible = true
		UiKit.playSound("rbxasset://sounds/bass.mp3", data.win and 1.3 or 0.7, 0.6)
		if data.draw then
			resultTitle.Text = "DRAW"
			resultTitle.TextColor3 = COL_DIM
			resultDetail.Text = "引き分け"
		else
			resultTitle.Text = data.win and "WIN！" or "LOSE…"
			resultTitle.TextColor3 = data.win and COL_GOLD or COL_BAD
			local delta = data.delta or 0
			resultDetail.Text = string.format(
				"VS %s（%s）\nレート %d → %d（%+d）\n通算 %d勝 %d敗",
				data.opponent or "?", data.reason == "leave" and "不戦勝" or "対戦",
				(data.rating or 1000) - delta, data.rating or 1000, delta,
				data.wins or 0, data.losses or 0
			)
		end

	elseif a == "toLobby" then
		result.Visible = false
		battle.Visible = false
		showLobby()

	elseif a == "practiceQ" then
		practiceLocked = false
		pracFeedback.Text = ""
		pracStreak.Text = "連続正解 " .. (data.streak or 0)
		lastPracChoices = data.choices
		showQuestion(data, pracChoices, pracText)
		UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.7, 0.25)

	elseif a == "practiceResult" then
		practiceLocked = true
		if data.correct then
			UiKit.playSound("rbxasset://sounds/electronicpingshort.wav", 1.2, 0.6)
			pracFeedback.TextColor3 = COL_GOOD
			pracFeedback.Text = "正解！"
		else
			UiKit.playSound("rbxasset://sounds/snap.mp3", 1, 0.7)
			pracFeedback.TextColor3 = COL_BAD
			pracFeedback.Text = "はずれ… 正解は「" .. ((lastPracChoices and lastPracChoices[data.correctIdx]) or "?") .. "」"
		end
		for i, b in ipairs(pracChoices) do
			b.AutoButtonColor = false
			if i == data.correctIdx then
				b.BackgroundColor3 = COL_GOOD
			end
		end
		if not data.correct then
			task.delay(1.8, function()
				C2S:FireServer({ action = "practiceNext" })
			end)
		end
	end
end)

showLobby()
