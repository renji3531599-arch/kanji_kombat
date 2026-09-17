--!nonstrict
-- 漢字コンバット サーバーエントリポイント
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
local MatchService = require(Modules:WaitForChild("MatchService"))
local PurchaseService = require(Modules:WaitForChild("PurchaseService"))

math.randomseed(os.time() + os.clock() * 1000)

-- ------------------------------------------------- world
local world = Instance.new("Folder")
world.Name = "KanjiKombatWorld"
world.Parent = workspace

LobbyService.build(world)
ArenaService.build(world)

MatchService.init({
	QuestionBank = QuestionBank,
	StatsService = StatsService,
	ArenaService = ArenaService,
	LobbyService = LobbyService,
	S2C = S2C,
	C2S = C2S,
})

PurchaseService.init({
	StatsService = StatsService,
	S2C = S2C,
})

-- クライアントからの操作 (対戦エントリー / 回答 / 練習モード) を受け取る。
-- ここを繋がないとサーバーは何も受信せず、練習モードは問題が1問も出ない。
C2S.OnServerEvent:Connect(function(player, data)
	local ok, err = pcall(MatchService.onRemote, player, data)
	if not ok then
		warn("[MatchService] onRemote: " .. tostring(err))
	end
	local shopOk, shopErr = pcall(PurchaseService.onRemote, player, data)
	if not shopOk then
		warn("[PurchaseService] onRemote: " .. tostring(shopErr))
	end
end)

-- ------------------------------------------------- profile plumbing
local function sanitizeProfile(profile)
	local ratings = {}
	for k, v in pairs(profile.ratings) do
		ratings[k] = v
	end
	return {
		ratings = ratings,
		wins = profile.wins,
		losses = profile.losses,
		streak = profile.streak,
		bestStreak = profile.bestStreak,
		coins = profile.coins or 0,
		xp = profile.xp or 0,
		level = profile.level or 1,
		correctAnswers = profile.correctAnswers or 0,
		answeredQuestions = profile.answeredQuestions or 0,
		bestCombo = profile.bestCombo or 0,
		daily = profile.daily or { battles = 0, claimed = false },
		inventory = profile.inventory or {},
		equipped = profile.equipped or { title = "rookie", aura = "none" },
		locale = profile.locale, -- 保存された表示言語 (未設定なら nil = 自動判定)
	}
end

RF.OnServerInvoke = function(player)
	return sanitizeProfile(StatsService.get(player))
end

Players.PlayerAdded:Connect(function(player)
	StatsService.load(player)
	task.spawn(function()
		PurchaseService.syncPasses(player)
	end)
end)

-- Studio で既に参加済みの場合
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		StatsService.load(player)
		PurchaseService.syncPasses(player)
	end)
end

-- ------------------------------------------------- loops
task.spawn(function()
	while true do
		local ok, err = pcall(MatchService.tick)
		if not ok then
			warn("[MatchService] " .. tostring(err))
		end
		task.wait(1)
	end
end)

print("[KanjiKombat] server ready / 起動完了")
print(string.format("[KanjiKombat] levels=%d, K10=%d, K01=%d questions",
	#Config.LEVELS, QuestionBank.count("K10"), QuestionBank.count("K01")))
