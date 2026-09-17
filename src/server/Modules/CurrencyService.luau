--!nonstrict
-- 通貨・所持品・デイリー報酬・ショップのサーバー側ロジック
-- Coins(無償) / Gems(有償) + 消費アイテム (hint, shield, secondChance など)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local CurrencyService = {}

local Profiles = nil -- StatsService.profiles を注入
local Dirty = nil
local S2C = nil

local econ = Config.ECONOMY

-- プロファイル初期値に通貨フィールドを追加
function CurrencyService.inject(dependencies)
	Profiles = dependencies.Profiles -- table [player] = profile
	Dirty = dependencies.Dirty
	S2C = dependencies.S2C
end

function CurrencyService.ensure(profile)
	if profile.coins == nil then profile.coins = econ.START_COINS end
	if profile.gems == nil then profile.gems = econ.START_GEMS end
	if profile.inventory == nil then profile.inventory = { hint = 2, shield = 1, secondChance = 0, reroll = 1 } end
	if profile.dailyStreak == nil then profile.dailyStreak = 0 end
	if profile.lastDailyClaim == nil then profile.lastDailyClaim = 0 end
	if profile.passXp == nil then profile.passXp = 0 end
	if profile.passTier == nil then profile.passTier = 0 end
	if profile.premiumPass == nil then profile.premiumPass = false end
	if profile.ownedCosmetics == nil then profile.ownedCosmetics = { titles = {"novice"}, arenas = {"default"}, emotes = {} } end
	if profile.equipped == nil then profile.equipped = { title = "novice", arena = "default", emote = "bow" } end
	if profile.vip == nil then profile.vip = false end
end

function CurrencyService.get(profile)
	CurrencyService.ensure(profile)
	return profile
end

local function send(player, action, data)
	data = data or {}
	data.action = action
	pcall(function() S2C:FireClient(player, data) end)
end

function CurrencyService.sendUpdate(player)
	local profile = Profiles[player]
	if not profile then return end
	CurrencyService.ensure(profile)
	send(player, "currencyUpdate", {
		coins = profile.coins,
		gems = profile.gems,
		inventory = profile.inventory,
		passXp = profile.passXp,
		passTier = profile.passTier,
		premium = profile.premiumPass,
	})
end

function CurrencyService.canAfford(profile, costCoins, costGems)
	CurrencyService.ensure(profile)
	return (profile.coins >= (costCoins or 0)) and (profile.gems >= (costGems or 0))
end

function CurrencyService.spend(player, costCoins, costGems, reason)
	local profile = Profiles[player]
	if not profile then return false end
	CurrencyService.ensure(profile)
	costCoins = costCoins or 0
	costGems = costGems or 0
	if profile.coins < costCoins or profile.gems < costGems then return false end
	profile.coins = profile.coins - costCoins
	profile.gems = profile.gems - costGems
	if Dirty then Dirty[player]=true end
	CurrencyService.sendUpdate(player)
	return true
end

function CurrencyService.grant(player, addCoins, addGems, reason)
	local profile = Profiles[player]
	if not profile then return end
	CurrencyService.ensure(profile)
	profile.coins = profile.coins + (addCoins or 0)
	profile.gems = profile.gems + (addGems or 0)
	if Dirty then Dirty[player]=true end
	CurrencyService.sendUpdate(player)
	-- トーストで獲得を演出
	if (addCoins or 0) > 0 or (addGems or 0) > 0 then
		local msg = ""
		if (addCoins or 0) > 0 then msg = msg .. "+"..addCoins.." Coins " end
		if (addGems or 0) > 0 then msg = msg .. "+"..addGems.." Gems" end
		send(player, "toast", { key = "toastReward", args = { msg = msg } })
	end
end

-- デイリー報酬
function CurrencyService.claimDaily(player)
	local profile = Profiles[player]
	if not profile then return { ok=false, reason="no_profile" } end
	CurrencyService.ensure(profile)
	local now = os.time()
	local last = profile.lastDailyClaim or 0
	-- 同日内は再取得不可 (簡易: 20時間クールダウン)
	if now - last < 20*3600 then
		return { ok=false, reason="too_soon", remain = 20*3600 - (now-last) }
	end
	local isNewDay = (now - last) >= 20*3600 and (now - last) < 48*3600
	if isNewDay then
		profile.dailyStreak = math.min(7, (profile.dailyStreak or 0) + 1)
	else
		-- 48時間以上空いたらリセット、初回は1
		if last == 0 then profile.dailyStreak = 1
		elseif now - last >= 48*3600 then profile.dailyStreak = 1
		else profile.dailyStreak = (profile.dailyStreak or 0) + 1
		end
	end
	profile.lastDailyClaim = now
	local streak = profile.dailyStreak
	local rewardCoins = Config.DAILY.REWARDS[streak] or 20
	local rewardGems = 0
	if streak == 7 then rewardGems = Config.DAILY.BONUS_GEMS_DAY7 end
	if profile.vip then rewardCoins = rewardCoins + 20 end -- VIPボーナス
	profile.coins = profile.coins + rewardCoins
	profile.gems = profile.gems + rewardGems
	if Dirty then Dirty[player]=true end
	CurrencyService.sendUpdate(player)
	return { ok=true, streak=streak, coins=rewardCoins, gems=rewardGems }
end

-- ショップ購入 (コイン/ジェム)
function CurrencyService.buyItem(player, category, key)
	local profile = Profiles[player]
	if not profile then return false end
	CurrencyService.ensure(profile)
	-- 価格表は Config.COSMETICS / ECONOMY から引く
	if category == "hint" then
		if CurrencyService.spend(player, econ.COST_HINT, 0, "hint") then
			profile.inventory.hint = (profile.inventory.hint or 0) + 1
			if Dirty then Dirty[player]=true end
			CurrencyService.sendUpdate(player)
			return true
		end
	elseif category == "shield" then
		if CurrencyService.spend(player, econ.COST_SHIELD_REFILL, 0, "shield") then
			profile.inventory.shield = (profile.inventory.shield or 0) + 1
			if Dirty then Dirty[player]=true end
			CurrencyService.sendUpdate(player)
			return true
		end
	elseif category == "reroll" then
		if CurrencyService.spend(player, econ.COST_REROLL_QUESTION, 0, "reroll") then
			profile.inventory.reroll = (profile.inventory.reroll or 0) + 1
			if Dirty then Dirty[player]=true end
			CurrencyService.sendUpdate(player)
			return true
		end
	elseif category == "cosmetic" then
		-- key = "title:legend" など
		local kind, id = string.match(key, "^(%w+):(.+)$")
		if not kind then return false end
		local list = Config.COSMETICS[string.upper(kind).."S"] or Config.COSMETICS[kind.."s"] or {}
		-- 互換: TITLES / ARENAS / EMOTES
		if kind=="title" then list = Config.COSMETICS.TITLES
		elseif kind=="arena" then list = Config.COSMETICS.ARENAS
		elseif kind=="emote" then list = Config.COSMETICS.EMOTES end
		local item = nil
		for _, it in ipairs(list) do if it.key==id then item=it break end end
		if not item then return false end
		-- 既所持チェック
		local owned = profile.ownedCosmetics
		local arrKey = kind.."s"
		if kind=="title" then arrKey="titles" elseif kind=="arena" then arrKey="arenas" elseif kind=="emote" then arrKey="emotes" end
		for _,k in ipairs(owned[arrKey] or {}) do if k==id then return false end end
		local costC = item.priceCoins or 0
		local costG = item.priceGems or 0
		if CurrencyService.spend(player, costC, costG, "cosmetic:"..key) then
			table.insert(owned[arrKey], id)
			if Dirty then Dirty[player]=true end
			CurrencyService.sendUpdate(player)
			return true
		end
	end
	return false
end

function CurrencyService.equip(player, kind, key)
	local profile = Profiles[player]
	if not profile then return false end
	CurrencyService.ensure(profile)
	local owned = profile.ownedCosmetics
	local arrKey = kind.."s"
	if kind=="title" then arrKey="titles" elseif kind=="arena" then arrKey="arenas" elseif kind=="emote" then arrKey="emotes" end
	local has=false
	for _,k in ipairs(owned[arrKey] or {}) do if k==key then has=true break end end
	if not has then return false end
	profile.equipped[kind]=key
	if Dirty then Dirty[player]=true end
	CurrencyService.sendUpdate(player)
	return true
end

-- DevProduct 付与 (MarketplaceService.ProcessReceipt から呼ばれる)
function CurrencyService.grantDevProduct(player, productKey)
	local profile = Profiles[player]
	if not profile then return end
	CurrencyService.ensure(profile)
	if productKey=="coins_500" then CurrencyService.grant(player, 500, 0, "dev")
	elseif productKey=="coins_1500" then CurrencyService.grant(player, 1500, 0, "dev")
	elseif productKey=="coins_4000" then CurrencyService.grant(player, 4000, 0, "dev")
	elseif productKey=="gems_100" then CurrencyService.grant(player, 0, 100, "dev")
	elseif productKey=="gems_550" then CurrencyService.grant(player, 0, 550, "dev")
	elseif productKey=="streak_saver" then profile.inventory.streakSaver = (profile.inventory.streakSaver or 0)+1
	elseif productKey=="double_xp_1h" then profile.boosts = profile.boosts or {}; profile.boosts.doubleXpUntil = os.time()+3600
	elseif productKey=="battle_pass_premium" then profile.premiumPass=true
	end
	if Dirty then Dirty[player]=true end
	CurrencyService.sendUpdate(player)
end

return CurrencyService
