--!strict

-- This script owns the lifetime of player data profiles. Keep gameplay systems
-- server-side and use DataManager's methods rather than editing profile data
-- directly from RemoteEvents.

local Players = game:GetService("Players")

-- Bootstrap shared runtime dependencies before requiring modules whose top
-- level code waits for these folders and RemoteEvents.
local ReplicatedStorageBootstrapper = require(script:WaitForChild("ReplicatedStorageBootstrapper"))
ReplicatedStorageBootstrapper:Init()

-- Build the physical development world before loading ProfileService or any
-- gameplay dependency. A later module error must not prevent the map existing.
local DevEnvironmentSetup = require(script:WaitForChild("DevEnvironmentSetup"))
DevEnvironmentSetup:Init()

local DataManager = require(script:WaitForChild("DataManager"))
local CollisionManager = require(script:WaitForChild("CollisionManager"))
local JobManager = require(script:WaitForChild("JobManager"))
local WasherServer = require(script:WaitForChild("WasherServer"))
local EquipmentManager = require(script:WaitForChild("EquipmentManager"))
local ShopServer = require(script:WaitForChild("ShopServer"))
local MonetizationManager = require(script:WaitForChild("MonetizationManager"))
local PetServer = require(script:WaitForChild("PetServer"))

CollisionManager:Init()
JobManager:Init()
MonetizationManager:Init()
WasherServer:Init()
EquipmentManager:Init()
ShopServer:Init()
PetServer:Init()

local function createLeaderstats(player: Player, cash: number)
	if player.Parent == nil then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cashValue = Instance.new("NumberValue")
	cashValue.Name = "Cash"
	cashValue.Value = cash
	cashValue.Parent = leaderstats
end

local function onPlayerAdded(player: Player)

	task.spawn(function()
		local profile, loadError = DataManager:LoadProfile(player)

		if profile ~= nil then
			-- Native leaderboard values are created only after the authoritative
			-- profile has loaded. Water and equipment stay out of leaderstats.
			createLeaderstats(player, profile.Data.Cash)
			EquipmentManager:EquipPlayer(player)
		elseif player.Parent ~= nil then
			-- Do not reveal whether another server has this profile open.
			-- The generic message is safer and clearer for players.
			warn(string.format("Could not load data for %s: %s", player.Name, loadError or "Unknown error"))
			player:Kick("Your data could not be loaded. Please rejoin in a moment.")
		end
	end)
end

local function onPlayerRemoving(player: Player)
	DataManager:ReleaseProfile(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Covers players already present if this script is hot-reloaded in Studio.
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		DataManager:ReleaseProfile(player)
	end
end)
