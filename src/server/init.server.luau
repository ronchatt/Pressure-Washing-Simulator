--!strict

-- This script owns the lifetime of player data profiles. Keep gameplay systems
-- server-side and use DataManager's methods rather than editing profile data
-- directly from RemoteEvents.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DEVELOPMENT_USER_ID = 151636877

-- Bootstrap shared runtime dependencies before requiring modules whose top
-- level code waits for these folders and RemoteEvents.
local ReplicatedStorageBootstrapper = require(script:WaitForChild("ReplicatedStorageBootstrapper"))
ReplicatedStorageBootstrapper:Init()

-- Build the physical development world before loading ProfileService or any
-- gameplay dependency. A later module error must not prevent the map existing.
local DevEnvironmentSetup = require(script:WaitForChild("DevEnvironmentSetup"))
DevEnvironmentSetup:Init()

local BenchJobSetup = require(script:WaitForChild("BenchJobSetup"))
BenchJobSetup:Init()

local DataManager = require(script:WaitForChild("DataManager"))
local CollisionManager = require(script:WaitForChild("CollisionManager"))
local BaseHubManager = require(script:WaitForChild("BaseHubManager"))
local VehicleManager = require(script:WaitForChild("VehicleManager"))
local GlobalLeaderboardManager = require(script:WaitForChild("GlobalLeaderboardManager"))
local JobManager = require(script:WaitForChild("JobManager"))
local WasherServer = require(script:WaitForChild("WasherServer"))
local EquipmentManager = require(script:WaitForChild("EquipmentManager"))
local ShopServer = require(script:WaitForChild("ShopServer"))
local MonetizationManager = require(script:WaitForChild("MonetizationManager"))
local PetServer = require(script:WaitForChild("PetServer"))
local WaterEconomyManager = require(script:WaitForChild("WaterEconomyManager"))
local TutorialServer = require(script:WaitForChild("TutorialServer"))

CollisionManager:Init()
BaseHubManager:Init()
VehicleManager:Init()
JobManager:Init()
MonetizationManager:Init()
WasherServer:Init()
EquipmentManager:Init()
ShopServer:Init()
PetServer:Init()
WaterEconomyManager:Init()
TutorialServer:Init()
GlobalLeaderboardManager:Init()

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
			-- One-time development grant requested by the owner. It is restricted
			-- to their exact account in Studio and records its claimed state in the
			-- profile so repeated test sessions cannot duplicate the cash.
			if RunService:IsStudio()
				and player.UserId == DEVELOPMENT_USER_ID
				and profile.Data.DevelopmentGrants.Cash100kV1 ~= true
			then
				if DataManager:AddCash(player, 100_000) then
					profile.Data.DevelopmentGrants.Cash100kV1 = true
					print("DEVELOPMENT: Granted RC_StudiosYT $100,000 test cash.")
				end
			end
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
