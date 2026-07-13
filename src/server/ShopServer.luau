--!strict

-- Server-only shop authority. Clients can request an action, but this module
-- verifies profile ownership, costs, and upgrade order before changing data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local SharedShopData = require(ReplicatedStorage.Shared.SharedShopData)
local VehicleManager = require(script.Parent:WaitForChild("VehicleManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PurchaseItemRequest = remotes:WaitForChild("PurchaseItemRequest") :: RemoteEvent
local EquipItemRequest = remotes:WaitForChild("EquipItemRequest") :: RemoteEvent
local PurchaseTankRequest = remotes:WaitForChild("PurchaseTankRequest") :: RemoteEvent

local ShopServer = {}
local initialized = false

local function contains(items: {string}, itemName: string): boolean
	for _, ownedName in items do
		if ownedName == itemName then
			return true
		end
	end

	return false
end

local function waitForData(player: Player)
	for _ = 1, 100 do
		local data = DataManager:GetData(player)
		if data ~= nil then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

local function syncWasherSpeed(player: Player)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end

	local washer = SharedShopData.Washers[data.EquippedWasher]
	if washer ~= nil then
		player:SetAttribute("WasherCleanSpeed", washer.CleanSpeed)
	end
end

local function ensureComputerPrompt()
	local base = workspace:FindFirstChild("Base")
	local computer = base and base:FindFirstChild("Computer")
	if computer == nil then
		return
	end

	local promptParent: BasePart? = nil
	if computer:IsA("Model") then
		promptParent = computer.PrimaryPart or computer:FindFirstChildWhichIsA("BasePart", true)
	elseif computer:IsA("BasePart") then
		promptParent = computer
	end
	if promptParent == nil or promptParent:FindFirstChild("ShopPrompt") ~= nil then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Base Computer"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent
end

local function purchaseItem(player: Player, category: string, itemName: string)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end

	if category == "Washers" then
		local item = SharedShopData.Washers[itemName]
		if item == nil or contains(data.OwnedWashers, itemName) or not DataManager:DeductCash(player, item.Cost) then
			return
		end
		table.insert(data.OwnedWashers, itemName)
	elseif category == "Trucks" then
		local item = SharedShopData.Trucks[itemName]
		if item == nil or contains(data.OwnedTrucks, itemName) or not DataManager:DeductCash(player, item.Cost) then
			return
		end
		table.insert(data.OwnedTrucks, itemName)
	end
end

local function equipItem(player: Player, category: string, itemName: string)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end

	if category == "Washers" and SharedShopData.Washers[itemName] ~= nil and contains(data.OwnedWashers, itemName) then
		data.EquippedWasher = itemName
		syncWasherSpeed(player)
	elseif category == "Trucks" and SharedShopData.Trucks[itemName] ~= nil and contains(data.OwnedTrucks, itemName) then
		data.EquippedTruck = itemName
		VehicleManager:SpawnVehicle(player)
	end
end

local function purchaseTank(player: Player, tankID: string)
	local data = DataManager:GetData(player)
	local tier = SharedShopData.Tanks[tankID]
	if data == nil or tier == nil or data.MaxWater ~= tier.RequiredMaxWater then
		return
	end

	if not DataManager:DeductCash(player, tier.Cost) then
		return
	end

	data.MaxWater = tier.NewMaxWater
	data.Water = math.min(data.Water, data.MaxWater)
end

function ShopServer:Init()
	if initialized then
		return
	end
	initialized = true

	ensureComputerPrompt()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			if waitForData(player) ~= nil then
				syncWasherSpeed(player)
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			if waitForData(player) ~= nil then
				syncWasherSpeed(player)
			end
		end)
	end

	PurchaseItemRequest.OnServerEvent:Connect(function(player, category, itemName)
		if typeof(category) == "string" and typeof(itemName) == "string" then
			purchaseItem(player, category, itemName)
		end
	end)

	EquipItemRequest.OnServerEvent:Connect(function(player, category, itemName)
		if typeof(category) == "string" and typeof(itemName) == "string" then
			equipItem(player, category, itemName)
		end
	end)

	PurchaseTankRequest.OnServerEvent:Connect(function(player, tankID)
		if typeof(tankID) == "string" then
			purchaseTank(player, tankID)
		end
	end)
end

return ShopServer
