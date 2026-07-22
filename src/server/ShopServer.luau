--!strict

-- Server-only shop authority. Clients can request an action, but this module
-- verifies profile ownership, costs, and upgrade order before changing data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local VehicleManager = require(script.Parent:WaitForChild("VehicleManager"))
local SharedShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedShopData"))
local EquipmentManager = require(script.Parent:WaitForChild("EquipmentManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PurchaseItemRequest = remotes:WaitForChild("PurchaseItemRequest") :: RemoteEvent
local EquipItemRequest = remotes:WaitForChild("EquipItemRequest") :: RemoteEvent
local PurchaseTankRequest = remotes:WaitForChild("PurchaseTankRequest") :: RemoteEvent
local ShopStateRequest = remotes:WaitForChild("ShopStateRequest") :: RemoteEvent
local ShopStateChanged = remotes:WaitForChild("ShopStateChanged") :: RemoteEvent

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

local function syncWasherStats(player: Player)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end

	local washer = SharedShopData.Washers[data.EquippedWasher]
	if washer ~= nil then
		player:SetAttribute("WasherCleanSpeed", washer.CleanSpeed)
		player:SetAttribute("WasherSprayWidth", washer.SprayWidth)
		player:SetAttribute("WasherWaterEfficiency", washer.WaterEfficiency)
		player:SetAttribute("WasherEffectiveRange", washer.EffectiveRange)
		player:SetAttribute("EquippedWasher", data.EquippedWasher)
	end
end

local function sendShopState(player: Player, notice: string?, success: boolean?)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end
	ShopStateChanged:FireClient(player, {
		OwnedWashers = table.clone(data.OwnedWashers),
		EquippedWasher = data.EquippedWasher,
		OwnedTrucks = table.clone(data.OwnedTrucks),
		EquippedTruck = data.EquippedTruck,
		Cash = data.Cash,
		MaxWater = data.MaxWater,
		Level = data.Level,
		Notice = notice,
		Success = success,
	})
end

local function ensureComputerPrompt()
	local computer = Workspace:FindFirstChild("Computer with desk", true)
	if computer == nil then
		warn("ShopServer could not find Workspace['Computer with desk']")
		return
	end

	local promptParent: BasePart? = nil
	if computer:IsA("Model") then
		promptParent = computer.PrimaryPart or computer:FindFirstChildWhichIsA("BasePart", true)
	elseif computer:IsA("BasePart") then
		promptParent = computer
	end
	if promptParent == nil then
		warn(string.format("Workspace.%s has no BasePart for its shop prompt", computer.Name))
		return
	end

	local existingPrompt = computer:FindFirstChild("ShopPrompt", true)
	local prompt: ProximityPrompt
	if existingPrompt ~= nil and existingPrompt:IsA("ProximityPrompt") then
		prompt = existingPrompt
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.Parent = promptParent
	end
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Computer with desk"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	print("ShopServer: linked shop functionality to Workspace['Computer with desk'].")
end

local function purchaseItem(player: Player, category: string, itemName: string)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end

	if category == "Washers" then
		local item = SharedShopData.Washers[itemName]
		if item == nil then
			sendShopState(player, "That washer does not exist.", false)
			return
		end
		if contains(data.OwnedWashers, itemName) then
			sendShopState(player, itemName .. " is already owned.", false)
			return
		end
		if data.Level < item.UnlockLevel then
			sendShopState(player, string.format("Reach level %d to unlock %s.", item.UnlockLevel, itemName), false)
			return
		end
		if item.RequiredWasher and not contains(data.OwnedWashers, item.RequiredWasher) then
			sendShopState(player, "Buy " .. item.RequiredWasher .. " first.", false)
			return
		end
		if not DataManager:DeductCash(player, item.Cost) then
			sendShopState(player, "Not enough cash.", false)
			return
		end
		table.insert(data.OwnedWashers, itemName)
		sendShopState(player, itemName .. " purchased!", true)
	elseif category == "Trucks" then
		local item = SharedShopData.Trucks[itemName]
		if item == nil or contains(data.OwnedTrucks, itemName) or not DataManager:DeductCash(player, item.Cost) then
			sendShopState(player, "Truck purchase failed.", false)
			return
		end
		table.insert(data.OwnedTrucks, itemName)
		sendShopState(player, itemName .. " purchased!", true)
	end
end

local function equipItem(player: Player, category: string, itemName: string)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end

	if category == "Washers" and SharedShopData.Washers[itemName] ~= nil and contains(data.OwnedWashers, itemName) then
		data.EquippedWasher = itemName
		syncWasherStats(player)
		EquipmentManager:EquipPlayer(player)
		sendShopState(player, itemName .. " equipped!", true)
	elseif category == "Trucks" and SharedShopData.Trucks[itemName] ~= nil and contains(data.OwnedTrucks, itemName) then
		data.EquippedTruck = itemName
		VehicleManager:RespawnIfSpawned(player)
		sendShopState(player, itemName .. " equipped!", true)
	else
		sendShopState(player, "You do not own that item.", false)
	end
end

local function purchaseTank(player: Player, tankID: string)
	local data = DataManager:GetData(player)
	local tier = SharedShopData.Tanks[tankID]
	if data == nil or tier == nil or data.MaxWater ~= tier.RequiredMaxWater then
		sendShopState(player, "Tank tiers must be purchased in order.", false)
		return
	end

	if not DataManager:DeductCash(player, tier.Cost) then
		sendShopState(player, "Not enough cash.", false)
		return
	end

	data.MaxWater = tier.NewMaxWater
	-- A tank upgrade includes a full refill so the benefit is immediately visible
	-- in the custom water meter and feels rewarding at the computer.
	data.Water = data.MaxWater
	DataManager:SyncWater(player)
	sendShopState(player, "Water tank upgraded!", true)
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
				syncWasherStats(player)
				sendShopState(player)
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			if waitForData(player) ~= nil then
				syncWasherStats(player)
				sendShopState(player)
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

	ShopStateRequest.OnServerEvent:Connect(function(player)
		sendShopState(player)
	end)
end

return ShopServer
