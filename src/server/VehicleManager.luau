--!strict

-- Player-requested truck spawning. Vehicles remain server-replicated while
-- the owner receives physics network ownership for responsive driving.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CollisionManager = require(script.Parent:WaitForChild("CollisionManager"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))

local VehicleManager = {}
local initialized = false
local spawnedVehicles: {[Player]: Model} = {}
local assignedSpots: {[Player]: BasePart} = {}
local lastSpawnRequest: {[Player]: number} = {}
local vehiclesFolder: Folder
local parkingFolder: Folder

local TEMPLATE_SOURCES = {
	["Basic Pickup"] = "A-Chassis 6C by Novena",
	["Flatbed Truck"] = "A-Chassis 6.81T by Novena",
}

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureTemplates()
	vehiclesFolder = ensureFolder(ReplicatedStorage, "Vehicles")
	for truckName, sourceName in TEMPLATE_SOURCES do
		local source = Workspace:FindFirstChild(sourceName)
		if vehiclesFolder:FindFirstChild(truckName) == nil and source and source:IsA("Model") then
			local template = source:Clone()
			template.Name = truckName
			template:SetAttribute("VehicleTemplate", true)
			template.Parent = vehiclesFolder
		end
		-- Artist vehicles remain visible while editing but become spawn templates
		-- during play so duplicate unowned chassis do not occupy the parking lot.
		if source then source:Destroy() end
	end
end

local function ensureParkingSpots()
	parkingFolder = ensureFolder(Workspace, "BaseParking")
	local center = Vector3.new(7.5, 0.15, 118.7)
	for index = 1, 8 do
		local existing = parkingFolder:FindFirstChild(string.format("TruckSpawn%02d", index))
		local spot: Part
		if existing and existing:IsA("Part") then
			spot = existing
		else
			if existing then existing:Destroy() end
			spot = Instance.new("Part")
			spot.Name = string.format("TruckSpawn%02d", index)
			spot.Parent = parkingFolder
		end
		local column = (index - 1) % 4
		local row = math.floor((index - 1) / 4)
		spot.Size = Vector3.new(12, 0.3, 20)
		spot.Position = center + Vector3.new((column - 1.5) * 17, 0, (row - 0.5) * 22)
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanTouch = false
		spot.CanQuery = false
		spot.Transparency = 1
		spot:SetAttribute("TruckParkingSpot", true)
	end
end

local function destroyVehicle(player: Player)
	local vehicle = spawnedVehicles[player]
	if vehicle then vehicle:Destroy() end
	spawnedVehicles[player] = nil
	assignedSpots[player] = nil
end

local function chooseSpot(player: Player): BasePart?
	local occupied: {[BasePart]: boolean} = {}
	for owner, spot in assignedSpots do
		if owner ~= player and owner.Parent ~= nil then occupied[spot] = true end
	end
	local spots: {BasePart} = {}
	for _, child in parkingFolder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("TruckParkingSpot") == true then table.insert(spots, child) end
	end
	table.sort(spots, function(a, b) return a.Name < b.Name end)
	for _, spot in spots do if not occupied[spot] then return spot end end
	return spots[1]
end

local function configureSeat(vehicle: Model, owner: Player)
	local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat == nil then return end
	local prompt = seat:FindFirstChild("DrivePrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then prompt:Destroy(); prompt = nil end
	if prompt == nil then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DrivePrompt"
		prompt.Parent = seat
	end
	local typedPrompt = prompt :: ProximityPrompt
	typedPrompt.ActionText = "Drive"
	typedPrompt.ObjectText = owner.DisplayName .. "'s Truck"
	typedPrompt.KeyboardKeyCode = Enum.KeyCode.E
	typedPrompt.MaxActivationDistance = 10
	typedPrompt.RequiresLineOfSight = false
	typedPrompt.Triggered:Connect(function(player)
		if player ~= owner then return end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then seat:Sit(humanoid) end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		typedPrompt.Enabled = seat.Occupant == nil
	end)
	vehicle.PrimaryPart = seat
end

function VehicleManager:SpawnVehicle(player: Player): boolean
	local now = os.clock()
	if lastSpawnRequest[player] and now - lastSpawnRequest[player] < 4 then return false end
	lastSpawnRequest[player] = now
	local data = DataManager:GetData(player)
	if data == nil then return false end
	local template = vehiclesFolder:FindFirstChild(data.EquippedTruck) or vehiclesFolder:FindFirstChild("Basic Pickup")
	if template == nil or not template:IsA("Model") then
		warn("VehicleManager has no template for " .. data.EquippedTruck)
		return false
	end
	local spot = chooseSpot(player)
	if spot == nil then return false end
	destroyVehicle(player)
	local vehicle = template:Clone()
	vehicle.Name = string.format("%s_%d", data.EquippedTruck, player.UserId)
	vehicle:SetAttribute("OwnerUserId", player.UserId)
	vehicle:SetAttribute("EquippedTruck", data.EquippedTruck)
	vehicle.Parent = ensureFolder(Workspace, "PlayerVehicles")
	configureSeat(vehicle, player)
	local boundsCFrame, boundsSize = vehicle:GetBoundingBox()
	local pivot = vehicle:GetPivot()
	local pivotAboveBottom = pivot.Position.Y - (boundsCFrame.Position.Y - boundsSize.Y * 0.5)
	local rotation = spot.CFrame - spot.Position
	vehicle:PivotTo(CFrame.new(spot.Position + Vector3.new(0, pivotAboveBottom + 0.2, 0)) * rotation)
	CollisionManager:AssignVehicle(vehicle)
	local primary = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart", true)
	if primary then
		pcall(function() primary:SetNetworkOwner(player) end)
	end
	spawnedVehicles[player] = vehicle
	assignedSpots[player] = spot
	return true
end

function VehicleManager:RespawnIfSpawned(player: Player)
	if spawnedVehicles[player] then
		lastSpawnRequest[player] = nil
		self:SpawnVehicle(player)
	end
end

function VehicleManager:Init()
	if initialized then return end
	initialized = true
	ensureTemplates()
	ensureParkingSpots()
	local base = Workspace:FindFirstChild("Base")
	local terminal = base and base:FindFirstChild("TruckSpawnStation", true)
	local prompt = terminal and terminal:FindFirstChild("SpawnTruckPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player) self:SpawnVehicle(player) end)
	else
		warn("VehicleManager could not find the Base truck spawn prompt")
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RespawnVehicleRequest")
	if remote:IsA("RemoteEvent") then remote.OnServerEvent:Connect(function(player) self:SpawnVehicle(player) end) end
	Players.PlayerRemoving:Connect(function(player)
		destroyVehicle(player)
		lastSpawnRequest[player] = nil
	end)
	print("VehicleManager: eight parking spaces and the Base spawn station are ready.")
end

return VehicleManager
