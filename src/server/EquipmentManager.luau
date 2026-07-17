--!strict

print("DIAGNOSTIC: EquipmentManager script is RUNNING.")

-- Server-owned washer lifecycle. Profile data chooses the template; clients
-- only receive the resulting Tool and cannot request arbitrary equipment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local washersInstance = ReplicatedStorage:WaitForChild("Washers")
assert(washersInstance:IsA("Folder"), "ReplicatedStorage.Washers must be a Folder")
local Washers = washersInstance :: Folder

local EquipmentManager = {}
local initialized = false
local equippingPlayers: {[Player]: boolean} = {}

local function configureHandle(tool: Tool): BasePart
	local existing = tool:FindFirstChild("Handle")
	if existing and existing:IsA("BasePart") then
		existing.Anchored = false
		existing.CanCollide = false
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 0.45, 2.2)
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.Color = Color3.fromRGB(50, 65, 80)
	handle.Material = Enum.Material.Metal
	handle.Parent = tool
	return handle
end

local function ensureBasicWasher(): Tool
	local existing = Washers:FindFirstChild("Basic Backpack")
	if existing and existing:IsA("Tool") then
		existing:SetAttribute("IsPressureWasher", true)
		configureHandle(existing)
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local tool = Instance.new("Tool")
	tool.Name = "Basic Backpack"
	tool.ToolTip = "Basic pressure washer"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("IsPressureWasher", true)
	configureHandle(tool)
	tool.Parent = Washers
	return tool
end

local function removeCurrentWashers(player: Player)
	local function cleanContainer(container: Instance?)
		if container == nil then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and (child:GetAttribute("IsPressureWasher") == true or Washers:FindFirstChild(child.Name) ~= nil) then
				child:Destroy()
			end
		end
	end

	cleanContainer(player:FindFirstChild("Backpack"))
	cleanContainer(player.Character)
end

function EquipmentManager:EquipPlayer(player: Player): Tool?
	if equippingPlayers[player] then
		return nil
	end
	equippingPlayers[player] = true
	task.delay(5, function()
		equippingPlayers[player] = nil
	end)
	print("DIAGNOSTIC: Attempting to give tool to:", player.Name)

	local data = DataManager:GetData(player)
	if data == nil or player.Parent == nil then
		equippingPlayers[player] = nil
		return nil
	end

	local backpackInstance = player:WaitForChild("Backpack")
	if not backpackInstance:IsA("Backpack") or player.Parent == nil then
		equippingPlayers[player] = nil
		return nil
	end

	local basicWasher = ensureBasicWasher()
	local requestedTemplate = Washers:WaitForChild(data.EquippedWasher, 2)
	local template: Tool = basicWasher
	if requestedTemplate and requestedTemplate:IsA("Tool") and requestedTemplate:FindFirstChild("Handle") then
		template = requestedTemplate
	elseif data.EquippedWasher ~= basicWasher.Name then
		warn(string.format("Washer '%s' is unavailable; equipping Basic Backpack for %s", data.EquippedWasher, player.Name))
	end

	removeCurrentWashers(player)
	local clone = template:Clone()
	clone:SetAttribute("IsPressureWasher", true)
	configureHandle(clone)
	clone.Parent = backpackInstance
	print("DIAGNOSTIC: Tool successfully added to backpack.")
	player:SetAttribute("EquippedWasher", clone.Name)
	equippingPlayers[player] = nil
	return clone
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			EquipmentManager:EquipPlayer(player)
		end)
	end)

	if player.Character then
		task.defer(function()
			EquipmentManager:EquipPlayer(player)
		end)
	end
end

function EquipmentManager:Init()
	if initialized then
		return
	end
	initialized = true

	ensureBasicWasher()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return EquipmentManager
