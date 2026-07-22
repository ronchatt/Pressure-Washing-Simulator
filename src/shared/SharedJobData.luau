--!strict

-- Read-only job metadata shared by the server and client. Server scripts still
-- decide whether a player is eligible and whether a reward is earned.

local SharedProgressionData = require(script.Parent:WaitForChild("SharedProgressionData"))

export type JobTemplate = {
	JobID: string,
	RequiredTier: string,
	TotalSegments: number,
	Reward: number,
	DisplayName: string,
	Difficulty: string,
	RecommendedWasher: string,
	JobType: string,
	CompletionThreshold: number,
	UnlockLevel: number,
	XPReward: number,
}

export type ComboJobTemplate = {
	JobID: string,
	DisplayName: string,
	IncludedJobIDs: {string},
	RequiredTier: string,
	Difficulty: string,
	RecommendedWasher: string,
	Reward: number,
}

local SharedJobData = {
	JobOrder = SharedProgressionData.JobOrder,
	Jobs = {
		-- Development driveway prototype reuses Bench_1 so the starter tier and
		-- existing phone button can launch the pixel-cleaning test immediately.
		Bench_1 = { JobID = "Bench_1", JobType = "Bench", DisplayName = "Neighborhood Bench", RequiredTier = "Benches", UnlockLevel = 1, Difficulty = "Easy", RecommendedWasher = "Basic Backpack", CompletionThreshold = 95, TotalSegments = 3456, Reward = 50, XPReward = 40 },
		Fence_1 = { JobID = "Fence_1", JobType = "Fence", DisplayName = "Garden Fence", RequiredTier = "Fences", UnlockLevel = 3, Difficulty = "Easy", RecommendedWasher = "Compact Washer", CompletionThreshold = 95, TotalSegments = 50, Reward = 225, XPReward = 70 },
		Car_1 = { JobID = "Car_1", JobType = "Car", DisplayName = "Stationary Car", RequiredTier = "Cars", UnlockLevel = 6, Difficulty = "Medium", RecommendedWasher = "Heavy Duty Washer", CompletionThreshold = 95, TotalSegments = 75, Reward = 500, XPReward = 120 },
		Driveway_1 = { JobID = "Driveway_1", JobType = "Driveway", DisplayName = "Concrete Driveway", RequiredTier = "Driveways", UnlockLevel = 10, Difficulty = "Medium", RecommendedWasher = "Professional Washer", CompletionThreshold = 98, TotalSegments = 125, Reward = 1_000, XPReward = 220 },
		SingleStoryHouse_1 = { JobID = "SingleStoryHouse_1", JobType = "House", DisplayName = "Single-Story House", RequiredTier = "Single-Story Houses", UnlockLevel = 15, Difficulty = "Hard", RecommendedWasher = "Industrial Washer", CompletionThreshold = 98, TotalSegments = 250, Reward = 2_500, XPReward = 450 },
		Mansion_1 = { JobID = "Mansion_1", JobType = "Mansion", DisplayName = "Luxury Mansion", RequiredTier = "Mansions", UnlockLevel = 22, Difficulty = "Extreme", RecommendedWasher = "HydroMax Washer", CompletionThreshold = 98, TotalSegments = 500, Reward = 7_500, XPReward = 900 },
	} :: {[string]: JobTemplate},
	ComboJobOrder = { "NeighborhoodCleanup_1" },
	ComboJobs = {
		NeighborhoodCleanup_1 = {
			JobID = "NeighborhoodCleanup_1",
			DisplayName = "Neighborhood Cleanup",
			IncludedJobIDs = { "Bench_1", "Fence_1" },
			RequiredTier = "Fences",
			Difficulty = "Medium",
			RecommendedWasher = "Heavy Duty Washer",
			Reward = 350,
		},
	} :: {[string]: ComboJobTemplate},
}

return SharedJobData
