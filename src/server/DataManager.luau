--!strict

-- Server-only player data access layer. Clients must never require this module
-- or receive direct access to Profile.Data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local packages = shared:WaitForChild("Packages")
local ProfileService = require(packages:WaitForChild("ProfileService"))
local SharedProgressionData = require(shared:WaitForChild("SharedProgressionData"))

export type OwnedPetData = {
	UID: string,
	PetID: string,
}

export type PlayerData = {
	Cash: number,
	LifetimeCashEarned: number,
	XP: number,
	Level: number,
	Rebirths: number,
	TotalJobsCompleted: number,
	JobCompletions: {[string]: number},
	Water: number,
	MaxWater: number,
	EquippedWasher: string,
	EquippedTruck: string,
	OwnedWashers: {string},
	OwnedTrucks: {string},
	UnlockedJobTiers: {string},
	OwnedPets: {OwnedPetData},
	EquippedPet: string?,
	TutorialCompleted: boolean,
	DevelopmentGrants: {
		Cash100kV1: boolean,
	},
	Settings: {
		MusicVolume: number,
		SFXVolume: number,
	},
}

local PROFILE_TEMPLATE: PlayerData = {
	Cash = 0,
	LifetimeCashEarned = 0,
	XP = 0,
	Level = 1,
	Rebirths = 0,
	TotalJobsCompleted = 0,
	JobCompletions = {},
	-- Water is the current fill level; MaxWater is the backpack's capacity.
	Water = 100,
	MaxWater = 100,
	EquippedWasher = "Basic Backpack",
	EquippedTruck = "Basic Pickup",
	OwnedWashers = { "Basic Backpack" },
	OwnedTrucks = { "Basic Pickup" },
	UnlockedJobTiers = { "Benches" },
	OwnedPets = {},
	EquippedPet = nil,
	TutorialCompleted = false,
	DevelopmentGrants = {
		Cash100kV1 = false,
	},
	Settings = {
		MusicVolume = 0.5,
		SFXVolume = 0.5,
	},
}

local PROFILE_STORE_NAME = "PressureWashingSimulator_PlayerData_v1"
local PlayerProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, PROFILE_TEMPLATE)

local cashEarnedEvent = Instance.new("BindableEvent")
cashEarnedEvent.Name = "LifetimeCashEarnedChanged"

local DataManager = {
	ProfileTemplate = PROFILE_TEMPLATE,
	CashEarned = cashEarnedEvent.Event,
}

local profiles: {[Player]: any} = {}

local function isValidAmount(amount: number): boolean
	return typeof(amount) == "number" and amount == amount and amount ~= math.huge and amount ~= -math.huge
end

local function syncCashLeaderstat(player: Player, cash: number)
	-- The profile is authoritative. This value only mirrors it for Roblox's
	-- built-in player list and is never used as an economy source of truth.
	if player.Parent == nil then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats == nil then
		return
	end

	local cashValue = leaderstats:FindFirstChild("Cash")
	if cashValue ~= nil and cashValue:IsA("NumberValue") then
		cashValue.Value = cash
	end
end

local function syncWaterAttributes(player: Player, data: PlayerData)
	if player.Parent == nil then
		return
	end

	player:SetAttribute("Water", data.Water)
	player:SetAttribute("MaxWater", data.MaxWater)
end

local function syncSettingsAttributes(player: Player, data: PlayerData)
	if player.Parent == nil then return end
	player:SetAttribute("MusicVolume", math.clamp(data.Settings.MusicVolume, 0, 1))
	player:SetAttribute("SFXVolume", math.clamp(data.Settings.SFXVolume, 0, 1))
end

local function syncProgressionAttributes(player: Player, data: PlayerData)
	if player.Parent == nil then return end
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XPToNextLevel", SharedProgressionData.GetXPToNextLevel(data.XP))
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("TotalJobsCompleted", data.TotalJobsCompleted)
end

local function migrateProgressionData(data: PlayerData)
	-- Returning development profiles may already have later tiers unlocked. Lift
	-- their level to the matching milestone instead of taking access away.
	local minimumLevel = math.max(1, data.Level)
	for _, tierName in data.UnlockedJobTiers do
		for _, jobID in SharedProgressionData.JobOrder do
			local progression = SharedProgressionData.Jobs[jobID]
			if progression.TierName == tierName then
				minimumLevel = math.max(minimumLevel, progression.UnlockLevel)
			end
		end
	end
	data.XP = math.max(0, data.XP, SharedProgressionData.GetXPForLevel(minimumLevel))
	data.Level = SharedProgressionData.GetLevelFromXP(data.XP)
	for _, tierName in SharedProgressionData.GetUnlockedTiers(data.Level) do
		if not table.find(data.UnlockedJobTiers, tierName) then
			table.insert(data.UnlockedJobTiers, tierName)
		end
	end
end

function DataManager:GetProfile(player: Player)
	return profiles[player]
end

function DataManager:GetData(player: Player): PlayerData?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end

	return profile.Data
end

function DataManager:LoadProfile(player: Player)
	if profiles[player] ~= nil then
		return profiles[player]
	end

	-- The handler returns "Cancel" if another live server owns this session.
	-- This avoids force-loading a profile and disrupting the other session.
	local profile = PlayerProfileStore:LoadProfileAsync("Player_" .. player.UserId, function()
		return "Cancel"
	end)
	if profile == nil then
		return nil, "Profile is locked or unavailable"
	end

	profile:Reconcile()
	profile:ListenToRelease(function()
		-- ReleaseProfile clears this entry before deliberately ending a session.
		-- Only kick when ProfileService releases an otherwise active profile.
		local wasActiveProfile = profiles[player] == profile
		profiles[player] = nil
		if wasActiveProfile and player.Parent ~= nil then
			player:Kick("Your data session was opened elsewhere. Please rejoin.")
		end
	end)

	-- A player can leave while LoadProfileAsync yields. Releasing here prevents
	-- a stale session lock and does not attempt to modify departed-player data.
	if player.Parent == nil then
		profile:Release()
		return nil, "Player left before profile finished loading"
	end

	profiles[player] = profile
	migrateProgressionData(profile.Data)
	syncWaterAttributes(player, profile.Data)
	syncSettingsAttributes(player, profile.Data)
	syncProgressionAttributes(player, profile.Data)
	return profile
end

function DataManager:ReleaseProfile(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end

	profiles[player] = nil
	profile:Release()
end

function DataManager:AddCash(player: Player, amount: number): boolean
	if not isValidAmount(amount) or amount <= 0 then
		return false
	end

	local data = self:GetData(player)
	if data == nil then
		return false
	end

	data.Cash += amount
	syncCashLeaderstat(player, data.Cash)
	return true
end

function DataManager:AddEarnedCash(player: Player, amount: number): boolean
	if not isValidAmount(amount) or amount <= 0 then
		return false
	end
	local data = self:GetData(player)
	if data == nil then
		return false
	end
	data.Cash += amount
	data.LifetimeCashEarned += amount
	syncCashLeaderstat(player, data.Cash)
	cashEarnedEvent:Fire(player, data.LifetimeCashEarned)
	return true
end

function DataManager:DeductCash(player: Player, amount: number): boolean
	if not isValidAmount(amount) or amount <= 0 then
		return false
	end

	local data = self:GetData(player)
	if data == nil or data.Cash < amount then
		return false
	end

	data.Cash -= amount
	syncCashLeaderstat(player, data.Cash)
	return true
end

function DataManager:DeductWater(player: Player, amount: number): boolean
	if not isValidAmount(amount) or amount <= 0 then
		return false
	end

	local data = self:GetData(player)
	if data == nil or data.Water <= 0 then
		return false
	end

	data.Water = math.max(0, data.Water - amount)
	syncWaterAttributes(player, data)
	return true
end

function DataManager:RefillWater(player: Player, targetAmount: number?): boolean
	local data = self:GetData(player)
	if data == nil then
		return false
	end

	if targetAmount ~= nil then
		if not isValidAmount(targetAmount) or targetAmount < 0 then
			return false
		end
		data.Water = math.min(targetAmount, data.MaxWater)
	else
		data.Water = data.MaxWater
	end
	syncWaterAttributes(player, data)
	return true
end

function DataManager:SyncWater(player: Player): boolean
	local data = self:GetData(player)
	if data == nil then
		return false
	end

	syncWaterAttributes(player, data)
	return true
end

function DataManager:UnlockJobTier(player: Player, tierName: string): boolean
	if tierName == "" then
		return false
	end

	local data = self:GetData(player)
	if data == nil then
		return false
	end

	for _, unlockedTier in data.UnlockedJobTiers do
		if unlockedTier == tierName then
			return true
		end
	end

	table.insert(data.UnlockedJobTiers, tierName)
	return true
end

function DataManager:RecordJobCompletion(player: Player, jobID: string, xpReward: number)
	if jobID == "" or not isValidAmount(xpReward) or xpReward < 0 then return nil end
	local data = self:GetData(player)
	if data == nil then return nil end

	local previousLevel = data.Level
	data.TotalJobsCompleted += 1
	data.JobCompletions[jobID] = (data.JobCompletions[jobID] or 0) + 1
	data.XP += math.floor(xpReward)
	data.Level = SharedProgressionData.GetLevelFromXP(data.XP)
	local newlyUnlockedTiers = {}
	for _, tierName in SharedProgressionData.GetUnlockedTiers(data.Level) do
		if not table.find(data.UnlockedJobTiers, tierName) then
			table.insert(data.UnlockedJobTiers, tierName)
			table.insert(newlyUnlockedTiers, tierName)
		end
	end
	syncProgressionAttributes(player, data)
	return {
		XPReward = math.floor(xpReward),
		XP = data.XP,
		Level = data.Level,
		PreviousLevel = previousLevel,
		LeveledUp = data.Level > previousLevel,
		XPToNextLevel = SharedProgressionData.GetXPToNextLevel(data.XP),
		TotalJobsCompleted = data.TotalJobsCompleted,
		NewlyUnlockedTiers = newlyUnlockedTiers,
	}
end

function DataManager:CanRebirth(player: Player): boolean
	local data = self:GetData(player)
	if data == nil then return false end
	local rebirth = SharedProgressionData.Rebirth
	return data.Level >= rebirth.RequiredLevel
		and (data.JobCompletions[rebirth.RequiredJobID] or 0) > 0
		and data.Rebirths < rebirth.MaximumRebirths
end

function DataManager:IsTutorialCompleted(player: Player): boolean
	local data = self:GetData(player)
	return data ~= nil and data.TutorialCompleted == true
end

function DataManager:CompleteTutorial(player: Player): boolean
	local data = self:GetData(player)
	if data == nil then return false end
	data.TutorialCompleted = true
	player:SetAttribute("TutorialCompleted", true)
	return true
end

return DataManager
