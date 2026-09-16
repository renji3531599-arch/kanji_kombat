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
		locale = profile.locale, -- 保存された表示言語 (未設定なら nil = 自動判定)
	}
end

RF.OnServerInvoke = function(player)
	return sanitizeProfile(StatsService.get(player))
end

Players.PlayerAdded:Connect(function(player)
	StatsService.load(player)
end)

-- Studio で既に参加済みの場合
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(StatsService.load, player)
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
