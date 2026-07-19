--!strict

-- Read-only job metadata shared by the server and client. Server scripts still
-- decide whether a player is eligible and whether a reward is earned.

export type JobTemplate = {
	JobID: string,
	RequiredTier: string,
	TotalSegments: number,
	Reward: number,
	DisplayName: string,
	Difficulty: string,
	RecommendedWasher: string,
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
	JobOrder = {
		"Bench_1",
		"Fence_1",
		"Car_1",
		"Driveway_1",
		"SingleStoryHouse_1",
		"Mansion_1",
	},
	Jobs = {
		-- Development driveway prototype reuses Bench_1 so the starter tier and
		-- existing phone button can launch the pixel-cleaning test immediately.
		Bench_1 = { JobID = "Bench_1", DisplayName = "Neighborhood Bench", RequiredTier = "Benches", Difficulty = "Easy", RecommendedWasher = "Basic Backpack", TotalSegments = 3456, Reward = 50 },
		Fence_1 = { JobID = "Fence_1", DisplayName = "Garden Fence", RequiredTier = "Fences", Difficulty = "Easy", RecommendedWasher = "Basic Backpack", TotalSegments = 50, Reward = 225 },
		Car_1 = { JobID = "Car_1", DisplayName = "Stationary Car", RequiredTier = "Cars", Difficulty = "Medium", RecommendedWasher = "Heavy Duty Washer", TotalSegments = 75, Reward = 500 },
		Driveway_1 = { JobID = "Driveway_1", DisplayName = "Concrete Driveway", RequiredTier = "Driveways", Difficulty = "Medium", RecommendedWasher = "Heavy Duty Washer", TotalSegments = 125, Reward = 1_000 },
		SingleStoryHouse_1 = { JobID = "SingleStoryHouse_1", DisplayName = "Single-Story House", RequiredTier = "Single-Story Houses", Difficulty = "Hard", RecommendedWasher = "Professional Washer", TotalSegments = 250, Reward = 2_500 },
		Mansion_1 = { JobID = "Mansion_1", DisplayName = "Luxury Mansion", RequiredTier = "Mansions", Difficulty = "Extreme", RecommendedWasher = "Industrial Washer", TotalSegments = 500, Reward = 7_500 },
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
