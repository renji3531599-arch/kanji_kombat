--!nonstrict
-- Robux / ゲーム内ショップ。購入判定と付与はサーバーだけで行う。
-- 商品 ID が 0 の項目は安全な未設定状態として購入ボタンを無効化する。
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local PurchaseService = {}
local StatsService
local S2C
local productsById = {}
local passesById = {}
local itemsByKey = {}

local function send(player, action, data)
	data = data or {}
	data.action = action
	pcall(function()
		S2C:FireClient(player, data)
	end)
end

local function buildIndex()
	productsById, passesById, itemsByKey = {}, {}, {}
	for _, item in ipairs(Config.SHOP_ITEMS) do
		itemsByKey[item.key] = item
		if tonumber(item.id) and item.id > 0 then
			if item.kind == "gamepass" then
				passesById[item.id] = item
			else
				productsById[item.id] = item
			end
		end
	end
end

local function grantItem(player, item)
	if not item or not StatsService.isLoaded(player) then
		return false
	end
	local grant = item.grant or {}
	if grant.coins then
		StatsService.addCoins(player, grant.coins)
	end
	if grant.xp then
		StatsService.addXp(player, grant.xp)
	end
	if grant.item then
		StatsService.grantItem(player, grant.item)
	end
	return true
end

local function owned(player, item)
	if item.kind == "gamepass" and item.grant and item.grant.item then
		return StatsService.hasItem(player, item.grant.item)
	end
	return false
end

function PurchaseService.catalogFor(player)
	local catalog = {}
	for _, item in ipairs(Config.SHOP_ITEMS) do
		catalog[#catalog + 1] = {
			key = item.key,
			kind = item.kind,
			id = item.id,
			robux = item.robux,
			icon = item.icon,
			nameKey = item.nameKey,
			descKey = item.descKey,
			owned = owned(player, item),
			configured = tonumber(item.id) ~= nil and item.id > 0,
		}
	end
	return catalog
end

function PurchaseService.sendState(player)
	if not StatsService or not StatsService.isLoaded(player) then
		return
	end
	local profile = StatsService.get(player)
	send(player, "shopState", {
		coins = profile.coins,
		catalog = PurchaseService.catalogFor(player),
		inventory = profile.inventory,
		equipped = profile.equipped,
	})
end

function PurchaseService.syncPasses(player)
	if not StatsService or not StatsService.isLoaded(player) then
		return
	end
	for passId, item in pairs(passesById) do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok and owns then
			grantItem(player, item)
		end
	end
	PurchaseService.sendState(player)
end

function PurchaseService.grantProduct(player, item, purchaseId)
	if not grantItem(player, item) then
		return false
	end
	if purchaseId then
		StatsService.rememberReceipt(player, purchaseId)
	end
	local profile = StatsService.get(player)
	send(player, "purchaseGranted", {
		itemKey = item.key,
		nameKey = item.nameKey,
		coins = profile.coins,
		xp = profile.xp,
		level = profile.level,
	})
	PurchaseService.sendState(player)
	return true
end

local function receiptDecision(name)
	return Enum.ProductPurchaseDecision[name]
end

local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local item = productsById[receiptInfo.ProductId]
	if not item then
		-- このゲームの所有物でない商品は別の ProcessReceipt 実装に任せる。
		return receiptDecision("NotProcessedYet")
	end
	if not player or not StatsService.isLoaded(player) then
		return receiptDecision("NotProcessedYet")
	end
	local purchaseId = tostring(receiptInfo.PurchaseId or "")
	if purchaseId ~= "" and StatsService.receiptSeen(player, purchaseId) then
		return receiptDecision("PurchaseGranted")
	end
	if PurchaseService.grantProduct(player, item, purchaseId ~= "" and purchaseId or nil) then
		return receiptDecision("PurchaseGranted")
	end
	return receiptDecision("NotProcessedYet")
end

function PurchaseService.init(deps)
	StatsService = deps.StatsService
	S2C = deps.S2C
	buildIndex()

	-- ProcessReceipt はゲーム全体で一度だけ設定する。
	MarketplaceService.ProcessReceipt = processReceipt
	pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
			local item = passesById[passId]
			if purchased and item and StatsService.isLoaded(player) then
				grantItem(player, item)
				local profile = StatsService.get(player)
				send(player, "purchaseGranted", {
					itemKey = item.key,
					nameKey = item.nameKey,
					coins = profile.coins,
					xp = profile.xp,
					level = profile.level,
				})
				PurchaseService.sendState(player)
			end
		end)
	end)
end

function PurchaseService.onRemote(player, data)
	if type(data) ~= "table" then
		return
	end
	if data.action == "shopRefresh" then
		PurchaseService.sendState(player)
	elseif data.action == "equipItem" and type(data.slot) == "string" and type(data.itemKey) == "string" then
		if StatsService.equip(player, data.slot, data.itemKey) then
			PurchaseService.sendState(player)
		end
	end
end

return PurchaseService
