--!nonstrict
-- 漢字コンバット サーバーエントリポイント — 超拡張版
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ------------------------------------------------- remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local S2C = Instance.new("RemoteEvent")
S2C.Name = "ServerToClient"
S2C.Parent = remotes

local C2S = Instance.new("RemoteEvent")
C2S.Name = "ClientToServer"
C2S.Parent = remotes

local RF = Instance.new("RemoteFunction")
RF.Name = "GetProfile"
RF.Parent = remotes

-- ------------------------------------------------- modules
local Modules = script:WaitForChild("Modules")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))
local QuestionBank = require(Modules:WaitForChild("QuestionBank"))
local StatsService = require(Modules:WaitForChild("StatsService"))
local ArenaService = require(Modules:WaitForChild("ArenaService"))
local LobbyService = require(Modules:WaitForChild("LobbyService"))
local CurrencyService = require(Modules:WaitForChild("CurrencyService"))
local ProgressionService = require(Modules:WaitForChild("ProgressionService"))
local ShopService = require(Modules:WaitForChild("ShopService"))
local MatchService = require(Modules:WaitForChild("MatchService"))

math.randomseed(os.time() + os.clock() * 1000)

-- ------------------------------------------------- world
local world = Instance.new("Folder")
world.Name = "KanjiKombatWorld"
world.Parent = workspace

LobbyService.build(world)
ArenaService.build(world)

-- 通貨・成長の注入
CurrencyService.inject({ Profiles = StatsService.profiles, Dirty = StatsService.dirty, S2C = S2C })
ProgressionService.init({ Profiles = StatsService.profiles, Dirty = StatsService.dirty, S2C = S2C, CurrencyService = CurrencyService })
ShopService.init({ CurrencyService = CurrencyService, StatsService = StatsService, S2C = S2C })

MatchService.init({
	QuestionBank = QuestionBank,
	StatsService = StatsService,
	ArenaService = ArenaService,
	LobbyService = LobbyService,
	CurrencyService = CurrencyService,
	ProgressionService = ProgressionService,
	S2C = S2C,
	C2S = C2S,
})

-- クライアントからの操作を受け取る (統合ルーター)
C2S.OnServerEvent:Connect(function(player, data)
	-- Shop系は先に
	local ok, err = pcall(function()
		if type(data)=="table" and type(data.action)=="string" then
			if data.action=="buyDev" or data.action=="buyPass" or data.action=="buyWithCoins" or data.action=="equipCosmetic" or data.action=="claimDaily" then
				ShopService.onRemote(player, data)
				return
			end
		end
		MatchService.onRemote(player, data)
	end)
	if not ok then warn("[KanjiKombat] onRemote: "..tostring(err)) end
end)

-- ------------------------------------------------- profile plumbing
local function sanitizeProfile(profile)
	local ratings = {}
	for k, v in pairs(profile.ratings) do ratings[k]=v end
	return {
		ratings = ratings,
		wins = profile.wins, losses = profile.losses, streak = profile.streak, bestStreak = profile.bestStreak,
		locale = profile.locale,
		coins = profile.coins, gems = profile.gems,
		level = profile.level, xp = profile.xp,
		passXp = profile.passXp, passTier = profile.passTier, premiumPass = profile.premiumPass,
		inventory = profile.inventory,
		ownedCosmetics = profile.ownedCosmetics, equipped = profile.equipped,
		vip = profile.vip,
		missions = profile.missions,
		dailyStreak = profile.dailyStreak, lastDailyClaim = profile.lastDailyClaim,
		totalCorrect = profile.totalCorrect, totalPerfect = profile.totalPerfect, maxCombo = profile.maxCombo,
	}
end

RF.OnServerInvoke = function(player)
	local p = StatsService.get(player)
	-- 補完
	if CurrencyService then CurrencyService.ensure(p) end
	if ProgressionService then ProgressionService.ensure(p) end
	return sanitizeProfile(p)
end

Players.PlayerAdded:Connect(function(player)
	StatsService.load(player)
	-- 初回通貨同期
	task.delay(0.5, function()
		local prof = StatsService.get(player)
		if CurrencyService then CurrencyService.ensure(prof); CurrencyService.sendUpdate(player) end
		-- デイリーリマインダー
		task.wait(1)
		pcall(function() S2C:FireClient(player, { action="missionProgress", daily = prof.missions.daily, weekly = prof.missions.weekly }) end)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do task.spawn(StatsService.load, player) end

-- ------------------------------------------------- loops
task.spawn(function()
	while true do
		local ok, err = pcall(MatchService.tick)
		if not ok then warn("[MatchService] "..tostring(err)) end
		task.wait(1)
	end
end)

-- VIP デイリーボーナス (1時間ごとにチェック)
task.spawn(function()
	while true do
		task.wait(3600)
		for _, p in ipairs(Players:GetPlayers()) do
			local prof = StatsService.get(p)
			if prof and prof.vip then
				-- 何もしない (報酬はclaimで)
			end
		end
	end
end)

print("[KanjiKombat] server ready / 起動完了 — v2 豪華版")
print(string.format("[KanjiKombat] levels=%d, K10=%d, K01=%d questions | economy & battlepass loaded",
	#Config.LEVELS, QuestionBank.count("K10"), QuestionBank.count("K01")))
