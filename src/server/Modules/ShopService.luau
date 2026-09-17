--!nonstrict
-- Robux 課金 (MarketplaceService) のラッパー
-- Developer Products と GamePass を扱う。エディタ/Studio ではモックで動くように。

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local ShopService = {}
local CurrencyService, StatsService, S2C
local productIdToKey = {}
local gamePassIdToKey = {}

for _, p in ipairs(Config.PRODUCTS.DEV) do productIdToKey[p.id]=p.key end
for _, p in ipairs(Config.PRODUCTS.PASS) do gamePassIdToKey[p.id]=p.key end

function ShopService.init(deps)
	CurrencyService = deps.CurrencyService
	StatsService = deps.StatsService
	S2C = deps.S2C
	-- ProcessReceipt
	local function onReceipt(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local key = productIdToKey[receipt.ProductId]
		if not key then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local ok, err = pcall(function()
			if CurrencyService then
				CurrencyService.grantDevProduct(player, key)
			end
			if StatsService and StatsService.markDirty then
				StatsService.markDirty(player)
			end
		end)
		if not ok then warn("[Shop] receipt error "..tostring(err)) end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	pcall(function()
		MarketplaceService.ProcessReceipt = onReceipt
	end)
	-- GamePass 購入後の付与は PromptGamePassPurchaseFinished で (バグ修正: 全パス対応)
	pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, id, wasPurchased)
			if not wasPurchased then return end
			local key = gamePassIdToKey[id]
			if not key then return end
			local profile = StatsService and StatsService.get(plr)
			if not profile then return end
			profile.ownedCosmetics = profile.ownedCosmetics or { titles={}, arenas={}, emotes={} }
			if type(profile.ownedCosmetics.titles) ~= "table" then profile.ownedCosmetics.titles = {} end
			if type(profile.ownedCosmetics.arenas) ~= "table" then profile.ownedCosmetics.arenas = {} end
			if type(profile.ownedCosmetics.emotes) ~= "table" then profile.ownedCosmetics.emotes = {} end
			if key=="vip" then
				profile.vip=true
			elseif key=="arena_pack" then
				for _, a in ipairs({"sakura","night","legend"}) do
					local has=false
					for _,k in ipairs(profile.ownedCosmetics.arenas) do if k==a then has=true break end end
					if not has then table.insert(profile.ownedCosmetics.arenas, a) end
				end
			elseif key=="no_ads" then
				profile.noAds = true
			elseif key=="ultimate_pack" then
				for _, e in ipairs({"kiai","gloat"}) do
					local has=false
					for _,k in ipairs(profile.ownedCosmetics.emotes) do if k==e then has=true break end end
					if not has then table.insert(profile.ownedCosmetics.emotes, e) end
				end
				for _, t in ipairs({"oni","kami"}) do
					local has=false
					for _,k in ipairs(profile.ownedCosmetics.titles) do if k==t then has=true break end end
					if not has then table.insert(profile.ownedCosmetics.titles, t) end
				end
			end
			if StatsService and StatsService.markDirty then StatsService.markDirty(plr) end
			if CurrencyService then CurrencyService.sendUpdate(plr) end
			pcall(function() S2C:FireClient(plr, { action="gamePassGranted", key=key }) end)
		end)
	end)
end

function ShopService.promptDevProduct(player, productKey)
	for _, p in ipairs(Config.PRODUCTS.DEV) do
		if p.key==productKey then
			pcall(function() MarketplaceService:PromptProductPurchase(player, p.id) end)
			return true
		end
	end
	return false
end

function ShopService.promptGamePass(player, passKey)
	for _, p in ipairs(Config.PRODUCTS.PASS) do
		if p.key==passKey then
			pcall(function() MarketplaceService:PromptGamePassPurchase(player, p.id) end)
			return true
		end
	end
	return false
end

-- クライアントからの購入リクエスト (C2S)
function ShopService.onRemote(player, data)
	if data.action=="buyDev" and type(data.key)=="string" then
		ShopService.promptDevProduct(player, data.key)
	elseif data.action=="buyPass" and type(data.key)=="string" then
		ShopService.promptGamePass(player, data.key)
	elseif data.action=="buyWithCoins" and type(data.category)=="string" then
		if CurrencyService then
			local ok = CurrencyService.buyItem(player, data.category, data.key)
			pcall(function() S2C:FireClient(player, { action="shopResult", ok=ok, category=data.category, key=data.key }) end)
		end
	elseif data.action=="equipCosmetic" and type(data.kind)=="string" then
		if CurrencyService then
			local ok = CurrencyService.equip(player, data.kind, data.key)
			pcall(function() S2C:FireClient(player, { action="equipResult", ok=ok, kind=data.kind, key=data.key }) end)
		end
	elseif data.action=="claimDaily" then
		if CurrencyService then
			local res = CurrencyService.claimDaily(player)
			pcall(function() S2C:FireClient(player, { action="dailyResult", result=res }) end)
		end
	end
end

return ShopService
