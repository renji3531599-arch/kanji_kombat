--!nonstrict
-- 成長・バトルパス・ミッション・ランクのサーバー側
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local ProgressionService = {}
local Profiles, Dirty, S2C
local CurrencyService

function ProgressionService.init(deps)
	Profiles = deps.Profiles
	Dirty = deps.Dirty
	S2C = deps.S2C
	CurrencyService = deps.CurrencyService
end

local function send(player, action, data)
	data=data or {}
	data.action=action
	pcall(function() S2C:FireClient(player,data) end)
end

function ProgressionService.ensure(profile)
	if profile.level == nil then profile.level = 1 end
	if profile.xp == nil then profile.xp = 0 end
	if profile.passXp == nil then profile.passXp = 0 end
	if profile.passTier == nil then profile.passTier = 0 end
	if profile.missions == nil then
		profile.missions = { daily = {}, weekly = {}, lastDailyReset = 0, lastWeeklyReset = 0 }
	end
	if type(profile.missions.daily) ~= "table" then profile.missions.daily = {} end
	if type(profile.missions.weekly) ~= "table" then profile.missions.weekly = {} end
	if profile.achievements == nil then profile.achievements = {} end
	if profile.ownedCosmetics == nil then profile.ownedCosmetics = { titles = {"novice"}, arenas = {"default"}, emotes = {"bow"} } end
	if type(profile.ownedCosmetics.titles) ~= "table" then profile.ownedCosmetics.titles = {"novice"} end
	if type(profile.ownedCosmetics.arenas) ~= "table" then profile.ownedCosmetics.arenas = {"default"} end
	if type(profile.ownedCosmetics.emotes) ~= "table" then profile.ownedCosmetics.emotes = {"bow"} end
	if profile.inventory == nil then profile.inventory = { hint = 2, shield = 1, secondChance = 0, reroll = 1, streakSaver = 0 } end
end

function ProgressionService.xpForNext(level)
	local t = Config.PROGRESSION.XP_TABLE
	return t[level] or 200
end

function ProgressionService.addXp(player, amount, reason)
	local profile = Profiles[player]
	if not profile then return end
	ProgressionService.ensure(profile)
	if CurrencyService then CurrencyService.ensure(profile) end
	-- ブースト中なら2倍
	local mult = 1
	if profile.boosts and profile.boosts.doubleXpUntil and os.time() < profile.boosts.doubleXpUntil then
		mult = 2
	end
	local gain = math.floor(amount * mult + 0.5)
	profile.xp = profile.xp + gain
	profile.passXp = (profile.passXp or 0) + gain

	-- レベルアップ
	while profile.xp >= ProgressionService.xpForNext(profile.level) and profile.level < Config.PROGRESSION.MAX_LEVEL do
		profile.xp = profile.xp - ProgressionService.xpForNext(profile.level)
		profile.level = profile.level + 1
		-- レベルアップ報酬
		local coinReward = 50 + profile.level * 5
		profile.coins = (profile.coins or 0) + coinReward
		send(player, "levelUp", { level = profile.level, rewardCoins = coinReward })
	end

	-- バトルパス進捗
	local newTier = math.floor(profile.passXp / Config.PROGRESSION.PASS_XP_PER_TIER)
	if newTier > (profile.passTier or 0) then
		for tier = (profile.passTier or 0)+1, newTier do
			ProgressionService.grantPassReward(player, tier)
		end
		profile.passTier = newTier
	end

	if Dirty then Dirty[player]=true end
	send(player, "progressionUpdate", {
		level = profile.level, xp = profile.xp, xpNext = ProgressionService.xpForNext(profile.level),
		passXp = profile.passXp, passTier = profile.passTier,
		mult = mult,
	})
end

function ProgressionService.grantPassReward(player, tier)
	local profile = Profiles[player]
	if not profile then return end
	local entry = nil
	for _, r in ipairs(Config.PASS_REWARDS) do if r.tier==tier then entry=r break end end
	if not entry then return end
	-- 無料報酬は全員
	if entry.free then
		if entry.free.coins then profile.coins = (profile.coins or 0) + entry.free.coins end
		if entry.free.gems then profile.gems = (profile.gems or 0) + entry.free.gems end
		if entry.free.shield then profile.inventory = profile.inventory or {}; profile.inventory.shield = (profile.inventory.shield or 0)+(entry.free.shield or 0) end
	end
	-- プレミアムは所有者のみ (バグ修正: emote/skin/title の付与漏れ)
	if profile.premiumPass and entry.premium then
		if entry.premium.gems then profile.gems = (profile.gems or 0) + entry.premium.gems end
		if entry.premium.coins then profile.coins = (profile.coins or 0) + entry.premium.coins end
		profile.ownedCosmetics = profile.ownedCosmetics or { titles={}, arenas={}, emotes={} }
		if type(profile.ownedCosmetics.titles) ~= "table" then profile.ownedCosmetics.titles = {} end
		if type(profile.ownedCosmetics.arenas) ~= "table" then profile.ownedCosmetics.arenas = {} end
		if type(profile.ownedCosmetics.emotes) ~= "table" then profile.ownedCosmetics.emotes = {} end
		if entry.premium.titleEn or entry.premium.titleJa then
			-- 既存タイトルキーにマッピング (Apprentice->apprentice 等)
			local en = entry.premium.titleEn and string.lower(entry.premium.titleEn) or nil
			local key = en
			-- 既知の対応: なければ tier キーをフォールバック
			if not key or key == "" then key = "tier"..tier end
			-- 重複チェック
			local has = false
			for _,k in ipairs(profile.ownedCosmetics.titles) do if k==key then has=true break end end
			if not has then table.insert(profile.ownedCosmetics.titles, key) end
		end
		if entry.premium.arena then
			local has=false
			for _,k in ipairs(profile.ownedCosmetics.arenas) do if k==entry.premium.arena then has=true break end end
			if not has then table.insert(profile.ownedCosmetics.arenas, entry.premium.arena) end
		end
		if entry.premium.emote then
			local has=false
			for _,k in ipairs(profile.ownedCosmetics.emotes) do if k==entry.premium.emote then has=true break end end
			if not has then table.insert(profile.ownedCosmetics.emotes, entry.premium.emote) end
		end
		if entry.premium.skin then
			-- skin は称号として扱う (gold_kanji など)
			local has=false
			for _,k in ipairs(profile.ownedCosmetics.titles) do if k==entry.premium.skin then has=true break end end
			if not has then table.insert(profile.ownedCosmetics.titles, entry.premium.skin) end
		end
	end
	if Dirty then Dirty[player]=true end
	send(player, "passReward", { tier = tier, free = entry.free, premium = entry.premium, isPremium = profile.premiumPass })
end

-- ミッション進行
function ProgressionService.progressMission(player, key, amount)
	local profile = Profiles[player]
	if not profile then return end
	ProgressionService.ensure(profile)
	amount = amount or 1
	local now = os.time()
	-- 日次リセット (24h)
	if now - (profile.missions.lastDailyReset or 0) > 24*3600 then
		profile.missions.daily = {}
		profile.missions.lastDailyReset = now
		for _, m in ipairs(Config.MISSIONS.DAILY) do profile.missions.daily[m.key]=0 end
	end
	if now - (profile.missions.lastWeeklyReset or 0) > 7*24*3600 then
		profile.missions.weekly = {}
		profile.missions.lastWeeklyReset = now
		for _, m in ipairs(Config.MISSIONS.WEEKLY) do profile.missions.weekly[m.key]=0 end
	end
	-- 初期化
	if not next(profile.missions.daily) then
		for _, m in ipairs(Config.MISSIONS.DAILY) do profile.missions.daily[m.key]=0 end
	end
	if not next(profile.missions.weekly) then
		for _, m in ipairs(Config.MISSIONS.WEEKLY) do profile.missions.weekly[m.key]=0 end
	end
	-- 単純加算: key が daily/weekly にあれば加算
	if profile.missions.daily[key] ~= nil then
		profile.missions.daily[key] = profile.missions.daily[key] + amount
		local def = nil
		for _, d in ipairs(Config.MISSIONS.DAILY) do if d.key==key then def=d break end end
		if def and profile.missions.daily[key] >= def.target and not profile.missions.daily[key.."_claimed"] then
			profile.missions.daily[key.."_claimed"]=true
			profile.coins = (profile.coins or 0) + def.rewardCoins
			ProgressionService.addXp(player, def.rewardXp, "mission")
			send(player, "missionComplete", { scope="daily", key=key, rewardCoins=def.rewardCoins, rewardXp=def.rewardXp })
		end
	end
	if profile.missions.weekly[key] ~= nil then
		profile.missions.weekly[key] = profile.missions.weekly[key] + amount
		local def=nil
		for _, d in ipairs(Config.MISSIONS.WEEKLY) do if d.key==key then def=d break end end
		if def and profile.missions.weekly[key] >= def.target and not profile.missions.weekly[key.."_claimed"] then
			profile.missions.weekly[key.."_claimed"]=true
			profile.coins = (profile.coins or 0) + def.rewardCoins
			ProgressionService.addXp(player, def.rewardXp, "mission")
			send(player, "missionComplete", { scope="weekly", key=key, rewardCoins=def.rewardCoins, rewardXp=def.rewardXp })
		end
	end
	if Dirty then Dirty[player]=true end
	send(player, "missionProgress", { daily = profile.missions.daily, weekly = profile.missions.weekly })
end

function ProgressionService.getMissions(player)
	local profile = Profiles[player]
	if not profile then return nil end
	ProgressionService.ensure(profile)
	return profile.missions
end

return ProgressionService
