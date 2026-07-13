--!strict

-- Shared collision policy: players and player-owned vehicles are visible to
-- one another but never create physical blocking or griefing opportunities.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local CollisionManager = {}
local initialized = false

local PLAYER_GROUP = "Players"
local VEHICLE_GROUP = "Vehicles"

local function ensureCollisionGroup(groupName: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
end

local function assignParts(model: Instance, groupName: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end

	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end)
end

function CollisionManager:AssignCharacter(character: Model)
	assignParts(character, PLAYER_GROUP)
end

function CollisionManager:AssignVehicle(vehicle: Model)
	assignParts(vehicle, VEHICLE_GROUP)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		CollisionManager:AssignCharacter(character)
	end)

	if player.Character ~= nil then
		CollisionManager:AssignCharacter(player.Character)
	end
end

function CollisionManager:Init()
	if initialized then
		return
	end
	initialized = true

	ensureCollisionGroup(PLAYER_GROUP)
	ensureCollisionGroup(VEHICLE_GROUP)
	PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(VEHICLE_GROUP, VEHICLE_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, VEHICLE_GROUP, false)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return CollisionManager
