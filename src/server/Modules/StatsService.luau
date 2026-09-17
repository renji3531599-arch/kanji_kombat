--!nonstrict
-- プロフィール、Elo、ランク、ゲーム内進行を一元管理するサービス。
-- Robux 購入の付与も必ずこのモジュールを経由し、クライアントの値を信用しない。
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))
local I18n = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("I18n"))

local StatsService = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore("KK_Profile_v2")
end)

local profiles = {} -- [player] = profile
local dirty = {}    -- [player] = true

local function todayKey()
	return os.date("!%Y-%m-%d")
end

local function defaultProfile()
	local ratings = {}
	for _, lv in ipairs(Config.LEVELS) do
		ratings[lv.key] = Config.DEFAULT_RATING
	end
	return {
		ratings = ratings,
	wins = 0,
	losses = 0,
	streak = 0,
	bestStreak = 0,
	coins = 0,
	xp = 0,
	level = 1,
	correctAnswers = 0,
	answeredQuestions = 0,
	bestCombo = 0,
	fastestMs = 0,
	locale = nil,
	uiLocale = nil,
	inventory = {},
	equipped = { title = "rookie", aura = "none" },
	daily = { date = todayKey(), battles = 0, claimed = false },
	processedReceipts = {},
	lastReward = nil,
	}
end

local function profileOf(player)
	return profiles[player]
end

local function normalizeProfile(profile)
	local base = defaultProfile()
	if type(profile) ~= "table" then
		return base
	end
	for key, default in pairs(base) do
		if type(default) ~= "table" and type(profile[key]) == type(default) then
			base[key] = profile[key]
		end
	end
	if type(profile.ratings) == "table" then
		for _, lv in ipairs(Config.LEVELS) do
			if type(profile.ratings[lv.key]) == "number" then
				base.ratings[lv.key] = math.floor(profile.ratings[lv.key])
			end
		end
	end
	for _, field in ipairs({ "inventory", "equipped", "daily", "processedReceipts" }) do
		if type(profile[field]) == "table" then
			base[field] = profile[field]
		end
	end
	if type(profile.locale) == "string" then
		base.locale = I18n.localeFromId(profile.locale)
	end
	if type(profile.uiLocale) == "string" then
		base.uiLocale = I18n.localeFromId(profile.uiLocale)
	end
	if type(base.daily.date) ~= "string" or base.daily.date ~= todayKey() then
		base.daily = { date = todayKey(), battles = 0, claimed = false }
	else
		base.daily.battles = math.max(0, math.floor(tonumber(base.daily.battles) or 0))
		base.daily.claimed = base.daily.claimed == true
	end
	base.coins = math.max(0, math.floor(tonumber(base.coins) or 0))
	base.xp = math.max(0, math.floor(tonumber(base.xp) or 0))
	base.level = math.max(1, math.floor(tonumber(base.level) or 1))
	return base
end

function StatsService.get(player)
	return profileOf(player) or defaultProfile()
end

function StatsService.isLoaded(player)
	return profileOf(player) ~= nil
end

local function keyFor(player)
	return "u_" .. player.UserId
end

function StatsService.load(player)
	local profile = defaultProfile()
	if store then
		local ok, data = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok and type(data) == "table" then
			profile = normalizeProfile(data)
		end
	end
	profiles[player] = profile
	StatsService.setupLeaderstats(player, profile)
end

local function updateLeaderstat(player, profile)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local wins = ls:FindFirstChild("勝数") or ls:FindFirstChild("Wins")
	if wins then
		wins.Value = profile.wins
	end
	local rating = ls:FindFirstChild("最高レート") or ls:FindFirstChild("Rating")
	if rating then
		local best = Config.DEFAULT_RATING
		for _, value in pairs(profile.ratings) do
			best = math.max(best, tonumber(value) or Config.DEFAULT_RATING)
		end
		rating.Value = best
	end
end

-- リーダーボードはプレイヤーの言語に合わせる。ただし値は同じ。
function StatsService.setupLeaderstats(player, profile)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local wins = ls:FindFirstChild("勝数") or ls:FindFirstChild("Wins")
	if not wins then
		wins = Instance.new("IntValue")
		wins.Parent = ls
	end
	wins.Name = (I18n.localeFromId(profile.uiLocale or profile.locale) == "ja") and "勝数" or "Wins"
	wins.Value = profile.wins

	local rating = ls:FindFirstChild("最高レート") or ls:FindFirstChild("Rating")
	if not rating then
		rating = Instance.new("IntValue")
		rating.Parent = ls
	end
	rating.Name = (I18n.localeFromId(profile.uiLocale or profile.locale) == "ja") and "最高レート" or "Rating"
	local best = Config.DEFAULT_RATING
	for _, value in pairs(profile.ratings) do
		best = math.max(best, tonumber(value) or Config.DEFAULT_RATING)
	end
	rating.Value = best
end

function StatsService.markDirty(player)
	if profiles[player] then
		dirty[player] = true
	end
end

function StatsService.addCoins(player, amount)
	local profile = profileOf(player)
	amount = math.floor(tonumber(amount) or 0)
	if not profile or amount == 0 then
		return profile and profile.coins or 0
	end
	profile.coins = math.max(0, profile.coins + amount)
	StatsService.markDirty(player)
	return profile.coins
end

local function xpForLevel(level)
	return 250 + (math.max(1, level) - 1) * 75
end

function StatsService.addXp(player, amount)
	local profile = profileOf(player)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if not profile or amount == 0 then
		return profile and profile.level or 1
	end
	profile.xp = profile.xp + amount
	while profile.xp >= xpForLevel(profile.level) do
		profile.xp = profile.xp - xpForLevel(profile.level)
		profile.level = profile.level + 1
		profile.coins = profile.coins + 25
	end
	StatsService.markDirty(player)
	return profile.level
end

function StatsService.grantItem(player, itemKey)
	local profile = profileOf(player)
	if not profile or type(itemKey) ~= "string" or itemKey == "" then
		return false
	end
	profile.inventory[itemKey] = true
	StatsService.markDirty(player)
	return true
end

function StatsService.hasItem(player, itemKey)
	local profile = profileOf(player)
	return profile and profile.inventory and profile.inventory[itemKey] == true or false
end

function StatsService.equip(player, slot, itemKey)
	local profile = profileOf(player)
	if not profile or (slot ~= "title" and slot ~= "aura") then
		return false
	end
	if itemKey ~= "rookie" and itemKey ~= "none" and not StatsService.hasItem(player, itemKey) then
		return false
	end
	profile.equipped[slot] = itemKey
	StatsService.markDirty(player)
	return true
end

function StatsService.recordAnswer(player, correct, elapsed)
	local profile = profileOf(player)
	if not profile then
		return
	end
	profile.answeredQuestions = profile.answeredQuestions + 1
	if correct then
		profile.correctAnswers = profile.correctAnswers + 1
	end
	if correct and tonumber(elapsed) and elapsed > 0 then
		local ms = math.floor(elapsed * 1000 + 0.5)
		if profile.fastestMs == 0 or ms < profile.fastestMs then
			profile.fastestMs = ms
		end
	end
	StatsService.markDirty(player)
end

function StatsService.awardMatch(player, won, bestCombo, correct, total)
	local profile = profileOf(player)
	if not profile then
		return { coins = 0, xp = 0 }
	end
	local progression = Config.PROGRESSION
	local coins = won and progression.COINS_WIN or progression.COINS_LOSS
	local xp = won and progression.XP_WIN or progression.XP_LOSS
	profile.daily.battles = profile.daily.battles + 1
	if bestCombo > profile.bestCombo then
		profile.bestCombo = bestCombo
	end
	if profile.daily.battles >= progression.DAILY_GOAL and not profile.daily.claimed then
		profile.daily.claimed = true
		coins = coins + 100
	end
	coins = coins + math.max(0, math.floor((correct or 0) * 2))
	xp = xp + math.max(0, math.floor((correct or 0) * progression.XP_CORRECT))
	StatsService.addCoins(player, coins)
	StatsService.addXp(player, xp)
	profile.lastReward = { coins = coins, xp = xp, correct = correct or 0, total = total or 0 }
	StatsService.markDirty(player)
	return { coins = coins, xp = xp }
end

function StatsService.awardPractice(player, correct)
	if correct then
		StatsService.addCoins(player, Config.PROGRESSION.COINS_PRACTICE)
		StatsService.addXp(player, Config.PROGRESSION.XP_CORRECT)
	end
end

-- 手動ロケールは保存。自動ロケールは今セッションの leaderstats だけ変える。
function StatsService.setLocale(player, code, source)
	local profile = profileOf(player)
	if not profile then
		return
	end
	local normalized = I18n.localeFromId(code)
	profile.uiLocale = normalized
	if source == "manual" then
		profile.locale = normalized
		StatsService.markDirty(player)
	end
	StatsService.setupLeaderstats(player, profile)
end

function StatsService.receiptSeen(player, purchaseId)
	local profile = profileOf(player)
	if not profile or type(purchaseId) ~= "string" then
		return false
	end
	for _, id in ipairs(profile.processedReceipts) do
		if id == purchaseId then
			return true
		end
	end
	return false
end

function StatsService.rememberReceipt(player, purchaseId)
	local profile = profileOf(player)
	if not profile or type(purchaseId) ~= "string" then
		return
	end
	profile.processedReceipts[#profile.processedReceipts + 1] = purchaseId
	while #profile.processedReceipts > 30 do
		table.remove(profile.processedReceipts, 1)
	end
	StatsService.markDirty(player)
end

-- Elo: winner/loser は player インスタンス。勝敗は必ずサーバーが決める。
function StatsService.applyResult(levelKey, winner, loser)
	local pw = profileOf(winner)
	local pl = profileOf(loser)
	if not pw or not pl then
		return 0
	end
	local rw = pw.ratings[levelKey] or Config.DEFAULT_RATING
	local rl = pl.ratings[levelKey] or Config.DEFAULT_RATING
	local ew = 1 / (1 + 10 ^ ((rl - rw) / 400))
	local dw = math.max(5, math.floor(Config.ELO_K * (1 - ew) + 0.5))
	pw.ratings[levelKey] = rw + dw
	pl.ratings[levelKey] = math.max(100, rl - dw)
	pw.wins = pw.wins + 1
	pl.losses = pl.losses + 1
	pw.streak = pw.streak + 1
	pl.streak = 0
	if pw.streak > pw.bestStreak then
		pw.bestStreak = pw.streak
	end
	updateLeaderstat(winner, pw)
	updateLeaderstat(loser, pl)
	StatsService.markDirty(winner)
	StatsService.markDirty(loser)
	return dw
end

function StatsService.applyDraw(playerA, playerB)
	local a, b = profileOf(playerA), profileOf(playerB)
	if a then a.streak = 0 end
	if b then b.streak = 0 end
	StatsService.markDirty(playerA)
	StatsService.markDirty(playerB)
end

local function save(player)
	local profile = profileOf(player)
	if not store or not profile then
		return
	end
	pcall(function()
		store:SetAsync(keyFor(player), profile)
	end)
end

function StatsService.savePlayer(player)
	save(player)
	dirty[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	-- MatchService の PlayerRemoving も同じイベントで不戦勝を確定する。
	-- 先に一度保存し、他のハンドラが追加した報酬を defer 後にもう一度保存できるようにする。
	if dirty[player] then
		save(player)
		dirty[player] = nil
	end
	task.defer(function()
		if profiles[player] and dirty[player] then
			save(player)
		end
		profiles[player] = nil
		dirty[player] = nil
	end)
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for player in pairs(profiles) do
		save(player)
	end
end)

return StatsService
