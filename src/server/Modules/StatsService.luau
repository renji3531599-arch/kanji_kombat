--!nonstrict
-- プロフィール (DataStore) とレーティング・通貨・成長の統合管理
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
-- 旧データ移行用
local legacyStore
pcall(function()
	legacyStore = DataStoreService:GetDataStore("KK_Profile_v1")
end)

local profiles = {} -- [player] = profile
local dirty = {}    -- [player] = true

-- 公開: 他サービスから参照できるように
StatsService.profiles = profiles
StatsService.dirty = dirty

local function defaultProfile()
	local ratings = {}
	for _, lv in ipairs(Config.LEVELS) do
		ratings[lv.key] = Config.DEFAULT_RATING
	end
	-- locale = プレイヤーが🌐ボタンで選んだ設定 (保存される)
	-- uiLocale = 今回のセッションの表示言語 (端末ロケールの自動判定 or locale)
	return {
		ratings = ratings, wins = 0, losses = 0, streak = 0, bestStreak = 0,
		locale = nil, uiLocale = nil,
		-- 通貨・成長・バトルパス
		coins = Config.ECONOMY.START_COINS,
		gems = Config.ECONOMY.START_GEMS,
		level = 1, xp = 0,
		passXp = 0, passTier = 0, premiumPass = false,
		inventory = { hint = 2, shield = 1, secondChance = 0, reroll = 1, streakSaver = 0 },
		dailyStreak = 0, lastDailyClaim = 0,
		ownedCosmetics = { titles = {"novice"}, arenas = {"default"}, emotes = {"bow"} },
		equipped = { title = "novice", arena = "default", emote = "bow" },
		vip = false,
		missions = { daily = {}, weekly = {}, lastDailyReset = 0, lastWeeklyReset = 0 },
		achievements = {},
		boosts = {},
		totalCorrect = 0, totalPerfect = 0, maxCombo = 0,
		createdAt = os.time(),
	}
end

local function localeOf(profile)
	local code = (profile and (profile.uiLocale or profile.locale)) or Config.DEFAULT_LOCALE
	return I18n.localeFromId(code)
end

function StatsService.get(player)
	return profiles[player] or defaultProfile()
end

local function keyFor(player)
	return "u_" .. player.UserId
end

local function migrateLegacy(data)
	-- 旧v1データがあれば新フィールドを補完
	if not data then return nil end
	return data
end

function StatsService.load(player)
	local profile = defaultProfile()
	local loaded = false
	if store then
		local ok, data = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok and type(data) == "table" then
			loaded = true
			-- マージ (新フィールドはデフォルトを上書き)
			for k,v in pairs(data) do
				profile[k] = v
			end
			-- ratings の欠損補完
			if type(data.ratings) == "table" then
				for _, lv in ipairs(Config.LEVELS) do
					if type(profile.ratings[lv.key]) ~= "number" then
						profile.ratings[lv.key] = Config.DEFAULT_RATING
					end
				end
			end
			if type(data.locale) == "string" then
				profile.locale = I18n.localeFromId(data.locale)
			end
		elseif legacyStore then
			local ok2, ldata = pcall(function() return legacyStore:GetAsync(keyFor(player)) end)
			if ok2 and type(ldata)=="table" then
				for k,v in pairs(ldata) do profile[k]=v end
				if type(ldata.ratings)=="table" then
					for _,lv in ipairs(Config.LEVELS) do
						if type(profile.ratings[lv.key])~="number" then profile.ratings[lv.key]=Config.DEFAULT_RATING end
					end
				end
			end
		end
	end
	-- 不足フィールドの補完 (旧データ互換)
	if type(profile.inventory) ~= "table" then profile.inventory = { hint = 2, shield = 1, secondChance = 0, reroll = 1, streakSaver = 0 } end
	if profile.inventory.hint == nil then profile.inventory.hint = 2 end
	if profile.inventory.shield == nil then profile.inventory.shield = 1 end
	if profile.inventory.secondChance == nil then profile.inventory.secondChance = 0 end
	if profile.inventory.reroll == nil then profile.inventory.reroll = 1 end
	if profile.inventory.streakSaver == nil then profile.inventory.streakSaver = 0 end
	if type(profile.ownedCosmetics) ~= "table" then profile.ownedCosmetics = { titles = {"novice"}, arenas = {"default"}, emotes = {"bow"} } end
	if type(profile.equipped) ~= "table" then profile.equipped = { title = "novice", arena = "default", emote = "bow" } end
	if profile.coins == nil then profile.coins = Config.ECONOMY.START_COINS end
	if profile.gems == nil then profile.gems = Config.ECONOMY.START_GEMS end
	if profile.level == nil then profile.level = 1 end
	if profile.xp == nil then profile.xp = 0 end
	if profile.boosts == nil then profile.boosts = {} end
	if profile.achievements == nil then profile.achievements = {} end
	if type(profile.missions) ~= "table" then profile.missions = { daily = {}, weekly = {}, lastDailyReset = 0, lastWeeklyReset = 0 } end
	if type(profile.missions.daily) ~= "table" then profile.missions.daily = {} end
	if type(profile.missions.weekly) ~= "table" then profile.missions.weekly = {} end
	-- 初回ミッション初期化
	if not next(profile.missions.daily) then
		for _, m in ipairs(Config.MISSIONS.DAILY) do profile.missions.daily[m.key]=0 end
	end
	if not next(profile.missions.weekly) then
		for _, m in ipairs(Config.MISSIONS.WEEKLY) do profile.missions.weekly[m.key]=0 end
	end
	profiles[player] = profile
	StatsService.setupLeaderstats(player, profile)
	-- 初回ボーナス: DataStoreが空ならプレゼント
	if not loaded then
		StatsService.markDirty(player)
	end
end

-- リーダーボード (勝数 / Wins) — 表示言語に合わせて名前を切り替える + レベルも表示
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
	wins.Name = (localeOf(profile) == "ja") and "勝数" or "Wins"
	wins.Value = profile.wins
	-- レベル表示
	local lvl = ls:FindFirstChild("レベル") or ls:FindFirstChild("Level")
	if not lvl then
		lvl = Instance.new("IntValue")
		lvl.Parent = ls
	end
	lvl.Name = (localeOf(profile)=="ja") and "レベル" or "Level"
	lvl.Value = profile.level or 1
end

-- クライアントから通知された表示言語 (source = "manual" のときだけ保存する)
function StatsService.setLocale(player, code, source)
	local profile = profiles[player]
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

function StatsService.markDirty(player)
	dirty[player] = true
end

local function save(player)
	local profile = profiles[player]
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

function StatsService.saveAll()
	for p,_ in pairs(profiles) do
		if dirty[p] then save(p) end
	end
end

-- Elo: winner/loser は player インスタンス + 追加報酬を付与
function StatsService.applyResult(levelKey, winner, loser)
	local pw = profiles[winner]
	local pl = profiles[loser]
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
	-- streak は後で勝敗確定時に連携: ここでは一旦記録
	-- ストリークセーバー消費チェックは MatchService 側で
	pw.streak = pw.streak + 1
	-- loserはセーバーがあればストリーク維持
	if pl.inventory and (pl.inventory.streakSaver or 0) > 0 then
		pl.inventory.streakSaver = pl.inventory.streakSaver - 1
		-- ストリークは減らさない (温情)
	else
		pl.streak = 0
	end
	if pw.streak > pw.bestStreak then
		pw.bestStreak = pw.streak
	end
	-- 統計の初期化
	if pw.totalCorrect == nil then pw.totalCorrect = 0 end
	if pl.totalCorrect == nil then pl.totalCorrect = 0 end
	-- leaderstats 更新 (日本語/英語の両名に対応)
	local lsW = winner:FindFirstChild("leaderstats")
	if lsW then
		local winsValue = lsW:FindFirstChild("勝数") or lsW:FindFirstChild("Wins")
		if winsValue then winsValue.Value = pw.wins end
		local lvlW = lsW:FindFirstChild("レベル") or lsW:FindFirstChild("Level")
		if lvlW then lvlW.Value = pw.level or 1 end
	end
	local lsL = loser:FindFirstChild("leaderstats")
	if lsL then
		local lvlL = lsL:FindFirstChild("レベル") or lsL:FindFirstChild("Level")
		if lvlL then lvlL.Value = pl.level or 1 end
		local winsL = lsL:FindFirstChild("勝数") or lsL:FindFirstChild("Wins")
		if winsL then winsL.Value = pl.wins end
	end
	StatsService.markDirty(winner)
	StatsService.markDirty(loser)
	return dw
end

-- 報酬付与ヘルパー
function StatsService.addCoins(player, n)
	local p = profiles[player]
	if not p then return end
	p.coins = (p.coins or 0) + n
	StatsService.markDirty(player)
end

Players.PlayerRemoving:Connect(function(player)
	if dirty[player] then
		save(player)
	end
	profiles[player] = nil
	dirty[player] = nil
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
