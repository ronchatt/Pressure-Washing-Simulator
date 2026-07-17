--!strict

-- Read-only job metadata shared by the server and client. Server scripts still
-- decide whether a player is eligible and whether a reward is earned.

export type JobTemplate = {
	JobID: string,
	RequiredTier: string,
	TotalSegments: number,
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
		Bench_1 = { JobID = "Bench_1", RequiredTier = "Benches", TotalSegments = 3456, Reward = 50 },
		Fence_1 = { JobID = "Fence_1", RequiredTier = "Fences", TotalSegments = 50, Reward = 225 },
		Car_1 = { JobID = "Car_1", RequiredTier = "Cars", TotalSegments = 75, Reward = 500 },
		Driveway_1 = { JobID = "Driveway_1", RequiredTier = "Driveways", TotalSegments = 125, Reward = 1_000 },
		SingleStoryHouse_1 = { JobID = "SingleStoryHouse_1", RequiredTier = "Single-Story Houses", TotalSegments = 250, Reward = 2_500 },
		Mansion_1 = { JobID = "Mansion_1", RequiredTier = "Mansions", TotalSegments = 500, Reward = 7_500 },
	} :: {[string]: JobTemplate},
}

return SharedJobData
