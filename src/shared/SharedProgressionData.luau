--!strict

-- Single source of truth for the first-run progression curve. Job and shop
-- modules consume this data so costs, unlocks, rewards, and recommendations
-- cannot silently drift apart.

export type JobProgression = {
	JobID: string,
	TierName: string,
	UnlockLevel: number,
	CashReward: number,
	XPReward: number,
	RecommendedWasher: string,
}

export type WasherProgression = {
	Name: string,
	Tier: number,
	UnlockLevel: number,
	Cost: number,
	CleanSpeed: number,
	SprayWidth: number,
	WaterEfficiency: number,
	EffectiveRange: number,
	AccentColor: Color3,
	Description: string,
	RequiredWasher: string?,
}

-- Cumulative XP at the beginning of each level. The first run is intended to
-- take roughly 35-45 completed jobs, with larger contracts advancing faster.
local cumulativeXP = {
	0, 40, 100, 180, 280, 400, 550, 730, 940, 1_180,
	1_460, 1_780, 2_140, 2_540, 3_000, 3_520, 4_100, 4_740,
	5_440, 6_200, 7_020, 7_900, 8_840, 9_840, 10_900,
}

local jobOrder = {
	"Bench_1",
	"Fence_1",
	"Car_1",
	"Driveway_1",
	"SingleStoryHouse_1",
	"Mansion_1",
}

local jobs: {[string]: JobProgression} = {
	Bench_1 = { JobID = "Bench_1", TierName = "Benches", UnlockLevel = 1, CashReward = 50, XPReward = 40, RecommendedWasher = "Basic Backpack" },
	Fence_1 = { JobID = "Fence_1", TierName = "Fences", UnlockLevel = 3, CashReward = 225, XPReward = 70, RecommendedWasher = "Compact Washer" },
	Car_1 = { JobID = "Car_1", TierName = "Cars", UnlockLevel = 6, CashReward = 500, XPReward = 120, RecommendedWasher = "Heavy Duty Washer" },
	Driveway_1 = { JobID = "Driveway_1", TierName = "Driveways", UnlockLevel = 10, CashReward = 1_000, XPReward = 220, RecommendedWasher = "Professional Washer" },
	SingleStoryHouse_1 = { JobID = "SingleStoryHouse_1", TierName = "Single-Story Houses", UnlockLevel = 15, CashReward = 2_500, XPReward = 450, RecommendedWasher = "Industrial Washer" },
	Mansion_1 = { JobID = "Mansion_1", TierName = "Mansions", UnlockLevel = 22, CashReward = 7_500, XPReward = 900, RecommendedWasher = "HydroMax Washer" },
}

local washerOrder = {
	"Basic Backpack",
	"Compact Washer",
	"Heavy Duty Washer",
	"Professional Washer",
	"Industrial Washer",
	"HydroMax Washer",
}

local washers: {[string]: WasherProgression} = {
	["Basic Backpack"] = {
		Name = "Basic Backpack", Tier = 1, UnlockLevel = 1, Cost = 0,
		CleanSpeed = 0.5, SprayWidth = 1, WaterEfficiency = 1, EffectiveRange = 1,
		AccentColor = Color3.fromRGB(45, 128, 190), Description = "Reliable starter washer",
	},
	["Compact Washer"] = {
		Name = "Compact Washer", Tier = 2, UnlockLevel = 3, Cost = 150,
		CleanSpeed = 0.62, SprayWidth = 1.06, WaterEfficiency = 1.08, EffectiveRange = 1.08,
		AccentColor = Color3.fromRGB(242, 190, 58), Description = "A nimble upgrade for fences and small jobs",
		RequiredWasher = "Basic Backpack",
	},
	["Heavy Duty Washer"] = {
		Name = "Heavy Duty Washer", Tier = 3, UnlockLevel = 6, Cost = 900,
		CleanSpeed = 0.85, SprayWidth = 1.12, WaterEfficiency = 1.18, EffectiveRange = 1.16,
		AccentColor = Color3.fromRGB(235, 151, 49), Description = "Strong pressure for vehicles",
		RequiredWasher = "Compact Washer",
	},
	["Professional Washer"] = {
		Name = "Professional Washer", Tier = 4, UnlockLevel = 10, Cost = 2_500,
		CleanSpeed = 1.2, SprayWidth = 1.2, WaterEfficiency = 1.35, EffectiveRange = 1.3,
		AccentColor = Color3.fromRGB(59, 201, 122), Description = "Efficient continuous-surface cleaning",
		RequiredWasher = "Heavy Duty Washer",
	},
	["Industrial Washer"] = {
		Name = "Industrial Washer", Tier = 5, UnlockLevel = 15, Cost = 7_500,
		CleanSpeed = 1.65, SprayWidth = 1.3, WaterEfficiency = 1.58, EffectiveRange = 1.44,
		AccentColor = Color3.fromRGB(172, 91, 235), Description = "Commercial pressure for large structures",
		RequiredWasher = "Professional Washer",
	},
	["HydroMax Washer"] = {
		Name = "HydroMax Washer", Tier = 6, UnlockLevel = 22, Cost = 20_000,
		CleanSpeed = 2.2, SprayWidth = 1.38, WaterEfficiency = 1.85, EffectiveRange = 1.58,
		AccentColor = Color3.fromRGB(58, 218, 232), Description = "Top-tier pressure for mansion contracts",
		RequiredWasher = "Industrial Washer",
	},
}

local Progression = {
	MaxLevel = #cumulativeXP,
	CumulativeXP = cumulativeXP,
	JobOrder = jobOrder,
	Jobs = jobs,
	WasherOrder = washerOrder,
	Washers = washers,
	Rebirth = {
		RequiredLevel = 25,
		RequiredJobID = "Mansion_1",
		CashBonusPerRebirth = 0.2,
		PressureBonusPerRebirth = 0.1,
		MaximumRebirths = 10,
	},
}

function Progression.GetLevelFromXP(xp: number): number
	local safeXP = math.max(0, math.floor(xp))
	local level = 1
	for candidate, requiredXP in cumulativeXP do
		if safeXP < requiredXP then break end
		level = candidate
	end
	return math.clamp(level, 1, #cumulativeXP)
end

function Progression.GetXPForLevel(level: number): number
	return cumulativeXP[math.clamp(math.floor(level), 1, #cumulativeXP)]
end

function Progression.GetXPToNextLevel(xp: number): number
	local level = Progression.GetLevelFromXP(xp)
	if level >= #cumulativeXP then return 0 end
	return math.max(0, cumulativeXP[level + 1] - math.max(0, math.floor(xp)))
end

function Progression.GetUnlockedTiers(level: number): {string}
	local unlocked = {}
	for _, jobID in jobOrder do
		local job = jobs[jobID]
		if level >= job.UnlockLevel and not table.find(unlocked, job.TierName) then
			table.insert(unlocked, job.TierName)
		end
	end
	return unlocked
end

return Progression
