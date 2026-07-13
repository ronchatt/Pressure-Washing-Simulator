--!strict

-- Server-owned truck lifecycle. Network ownership is handed to the driver so
-- configured VehicleSeat physics feels responsive while still replicating.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollisionManager = require(script.Parent:WaitForChild("CollisionManager"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))

local RespawnVehicleRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RespawnVehicleRequest") :: RemoteEvent

local VehicleManager = {}
local initialized = false
local spawnedTrucks: {[Player]: Model} = {}
local usedSpots: {[BasePart]: Player} = {}
local lastRespawnRequest: {[Player]: number} = {}

local function getAvailableSpot(): BasePart?
	local parking = workspace:FindFirstChild("BaseParking")
	if parking == nil then
		return nil
	end

	for _, instance in parking:GetChildren() do
		if instance:IsA("BasePart") and usedSpots[instance] == nil then
			return instance
		end
	end

	return nil
end

local function releaseSpotFor(player: Player)
	for spot, owner in usedSpots do
		if owner == player then
			usedSpots[spot] = nil
		end
	end
end

local function waitForProfileData(player: Player)
	for _ = 1, 100 do
		local data = DataManager:GetData(player)
		if data ~= nil then
			return data
		end
		task.wait(0.1)
	end

	return nil
end

local function configureSeat(player: Player, truck: Model)
	local seat = truck:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat == nil then
		return
	end

	local prompt = seat:FindFirstChild("DrivePrompt")
	if prompt == nil then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DrivePrompt"
		prompt.ActionText = "Drive"
		prompt.ObjectText = truck.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = seat
	end

	prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= player or seat.Occupant ~= nil then
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			seat:Sit(humanoid)
		end
	end)

	local function updatePrompt()
		prompt.Enabled = seat.Occupant == nil
	end
	seat:GetPropertyChangedSignal("Occupant"):Connect(updatePrompt)
	updatePrompt()
end

function VehicleManager:DestroyVehicle(player: Player)
	local truck = spawnedTrucks[player]
	spawnedTrucks[player] = nil
	releaseSpotFor(player)

	if truck ~= nil then
		truck:Destroy()
	end
end

function VehicleManager:SpawnVehicle(player: Player): Model?
	self:DestroyVehicle(player)

	local data = waitForProfileData(player)
	if data == nil then
		return nil
	end

	local vehicles = ReplicatedStorage:FindFirstChild("Vehicles")
	local template = vehicles and vehicles:FindFirstChild(data.EquippedTruck)
	local spot = getAvailableSpot()
	if template == nil or not template:IsA("Model") or spot == nil then
		return nil
	end

	local truck = template:Clone()
	if truck.PrimaryPart == nil then
		truck:Destroy()
		return nil
	end

	truck.Name = string.format("%s_%d", data.EquippedTruck, player.UserId)
	truck:PivotTo(spot.CFrame * CFrame.new(0, 3, 0))
	truck.Parent = workspace
	usedSpots[spot] = player
	spawnedTrucks[player] = truck

	CollisionManager:AssignVehicle(truck)
	pcall(function()
		truck.PrimaryPart:SetNetworkOwner(player)
	end)
	configureSeat(player, truck)

	return truck
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.spawn(function()
			VehicleManager:SpawnVehicle(player)
		end)
	end)

	if player.Character ~= nil then
		task.spawn(function()
			VehicleManager:SpawnVehicle(player)
		end)
	end
end

function VehicleManager:Init()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		self:DestroyVehicle(player)
		lastRespawnRequest[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	RespawnVehicleRequest.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastRespawnRequest[player] ~= nil and now - lastRespawnRequest[player] < 3 then
			return
		end
		lastRespawnRequest[player] = now
		self:SpawnVehicle(player)
	end)
end

return VehicleManager
