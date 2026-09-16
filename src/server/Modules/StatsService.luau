--!nonstrict
-- プロフィール (DataStore) とレーティング管理
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local StatsService = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore("KK_Profile_v1")
end)

local profiles = {} -- [player] = profile
local dirty = {}    -- [player] = true

local function defaultProfile()
	local ratings = {}
	for _, lv in ipairs(Config.LEVELS) do
		ratings[lv.key] = Config.DEFAULT_RATING
	end
	return { ratings = ratings, wins = 0, losses = 0, streak = 0, bestStreak = 0 }
end

function StatsService.get(player)
	return profiles[player] or defaultProfile()
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
			if type(data.wins) == "number" then
				profile.wins = data.wins
			end
			if type(data.losses) == "number" then
				profile.losses = data.losses
			end
			if type(data.streak) == "number" then
				profile.streak = data.streak
			end
			if type(data.bestStreak) == "number" then
				profile.bestStreak = data.bestStreak
			end
			if type(data.ratings) == "table" then
				for _, lv in ipairs(Config.LEVELS) do
					local r = data.ratings[lv.key]
					if type(r) == "number" then
						profile.ratings[lv.key] = r
					end
				end
			end
		end
	end
	profiles[player] = profile
	StatsService.setupLeaderstats(player, profile)
end

function StatsService.setupLeaderstats(player, profile)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "勝数"
	wins.Value = profile.wins
	wins.Parent = ls
	ls.Parent = player
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

-- Elo: winner/loser は player インスタンス
function StatsService.applyResult(levelKey, winner, loser)
	local pw = profiles[winner]
	local pl = profiles[loser]
	if not pw or not pl then
		return
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
	local ls = winner:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("勝数") then
		ls["勝数"].Value = pw.wins
	end
	StatsService.markDirty(winner)
	StatsService.markDirty(loser)
	return dw
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
