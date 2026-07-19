--!strict

-- Server-authoritative single and combo contracts. Dirt remains client-visual,
-- while the server owns eligibility, per-object coverage, water modifiers,
-- completion, progression unlocks, penalties, and rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local shared = ReplicatedStorage:WaitForChild("Shared")
local SharedJobData = require(shared:WaitForChild("SharedJobData"))
local SharedPetData = require(shared:WaitForChild("SharedPetData"))

export type JobTemplate = SharedJobData.JobTemplate
export type ActiveJobData = {
	JobID: string,
	DisplayName: string,
	IsCombo: boolean,
	IncludedJobIDs: {string},
	IncludedLookup: {[string]: boolean},
	CurrentTargetJobID: string?,
	SegmentsCleaned: number,
	TotalSegments: number,
	CleanedCoverage: number,
	TotalCoverage: number,
	PerJobSegmentsCleaned: {[string]: number},
	PerJobTotalSegments: {[string]: number},
	PerJobCleanedCoverage: {[string]: number},
	PerJobTotalCoverage: {[string]: number},
	CleanedInstances: {Instance},
	CleanedLookup: {[Instance]: boolean},
	WaterSource: string,
	RewardMultiplier: number,
	BaseReward: number,
}

local JOBS = SharedJobData.Jobs
local COMBO_JOBS = SharedJobData.ComboJobs
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AcceptJobRequest = remotes:WaitForChild("AcceptJobRequest") :: RemoteEvent
local QuitJobRequest = remotes:WaitForChild("QuitJobRequest") :: RemoteEvent
local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent
local JobStateRequest = remotes:WaitForChild("JobStateRequest") :: RemoteEvent

local JobManager = {}
local activeJobs: {[number]: ActiveJobData} = {}
local initialized = false
local JOB_COMPLETION_RATIO = 0.95
local TEMP_UNLOCKED_JOBS: {[string]: boolean} = { SingleStoryHouse_1 = true }
local NEXT_TIER_BY_JOB: {[string]: string} = {
	Bench_1 = "Fences",
	Fence_1 = "Cars",
	Car_1 = "Driveways",
	Driveway_1 = "Single-Story Houses",
	SingleStoryHouse_1 = "Mansions",
}

local function getSegmentWeight(segment: Instance): number
	local weight = segment:GetAttribute("DirtWeight")
	return if typeof(weight) == "number" and weight > 0 then math.clamp(weight, 0.05, 25) else 1
end

local function getRuntimeSegmentStats(jobID: string, fallback: number): (number, number)
	local count, coverage = 0, 0
	for _, segment in CollectionService:GetTagged("DirtSegment") do
		if segment:IsDescendantOf(Workspace) and segment:GetAttribute("JobID") == jobID then
			count += 1
			coverage += getSegmentWeight(segment)
		end
	end
	return if count > 0 then count else fallback, if count > 0 then coverage else fallback
end

local function hasUnlockedTier(player: Player, tierName: string): boolean
	local data = DataManager:GetData(player)
	return data ~= nil and table.find(data.UnlockedJobTiers, tierName) ~= nil
end

local function jobSiteExists(jobID: string): boolean
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local sites = environment and environment:FindFirstChild("JobSites")
	local site = sites and sites:FindFirstChild(jobID)
	return site ~= nil and site:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function getContract(jobID: string): (any?, {string}?, boolean)
	local single = JOBS[jobID]
	if single then return single, { jobID }, false end
	local combo = COMBO_JOBS[jobID]
	if combo then return combo, table.clone(combo.IncludedJobIDs), true end
	return nil, nil, false
end

local function contractAvailable(includedJobIDs: {string}): boolean
	for _, includedID in includedJobIDs do
		if not jobSiteExists(includedID) then return false end
	end
	return true
end

local function buildPerJobProgress(activeJob: ActiveJobData): {[string]: number}
	local progress: {[string]: number} = {}
	for _, jobID in activeJob.IncludedJobIDs do
		local total = activeJob.PerJobTotalCoverage[jobID] or 1
		progress[jobID] = math.clamp((activeJob.PerJobCleanedCoverage[jobID] or 0) / total * 100, 0, 100)
	end
	return progress
end

local function getNextTarget(activeJob: ActiveJobData): string?
	for _, jobID in activeJob.IncludedJobIDs do
		local total = activeJob.PerJobTotalCoverage[jobID] or 1
		if (activeJob.PerJobCleanedCoverage[jobID] or 0) < total * JOB_COMPLETION_RATIO then
			return jobID
		end
	end
	return nil
end

local function allTargetsComplete(activeJob: ActiveJobData): boolean
	return getNextTarget(activeJob) == nil
end

local function sendCatalogState(player: Player)
	local data = DataManager:GetData(player)
	if data == nil then return end
	local displayedTiers = table.clone(data.UnlockedJobTiers)
	for jobID in TEMP_UNLOCKED_JOBS do
		local job = JOBS[jobID]
		if job and not table.find(displayedTiers, job.RequiredTier) then table.insert(displayedTiers, job.RequiredTier) end
	end
	local availability: {[string]: boolean} = {}
	for jobID in JOBS do availability[jobID] = jobSiteExists(jobID) end
	for contractID, combo in COMBO_JOBS do availability[contractID] = contractAvailable(combo.IncludedJobIDs) end
	local activeJob = activeJobs[player.UserId]
	JobStateChanged:FireClient(player, {
		State = "Catalog",
		UnlockedJobTiers = displayedTiers,
		Availability = availability,
		ActiveJobID = activeJob and activeJob.JobID or nil,
	})
end

local function reject(player: Player, message: string, jobID: string?)
	JobStateChanged:FireClient(player, { State = "Rejected", Message = message, JobID = jobID })
end

local function makeState(activeJob: ActiveJobData, stateName: string)
	return {
		State = stateName,
		JobID = activeJob.JobID,
		DisplayName = activeJob.DisplayName,
		IsCombo = activeJob.IsCombo,
		IncludedJobIDs = table.clone(activeJob.IncludedJobIDs),
		CurrentTargetJobID = activeJob.CurrentTargetJobID,
		SegmentsCleaned = activeJob.SegmentsCleaned,
		TotalSegments = activeJob.TotalSegments,
		CleanedCoverage = activeJob.CleanedCoverage,
		TotalCoverage = activeJob.TotalCoverage,
		CompletionPercent = math.clamp(activeJob.CleanedCoverage / math.max(activeJob.TotalCoverage, 1) * 100, 0, 100),
		PerJobProgress = buildPerJobProgress(activeJob),
		WaterSource = activeJob.WaterSource,
		RewardMultiplier = activeJob.RewardMultiplier,
	}
end

function JobManager:GetJobTemplate(jobID: string): JobTemplate?
	return JOBS[jobID]
end

function JobManager:GetActiveJob(player: Player): ActiveJobData?
	return activeJobs[player.UserId]
end

function JobManager:IsJobPartOfActive(player: Player, jobID: string): boolean
	local activeJob = activeJobs[player.UserId]
	return activeJob ~= nil and activeJob.IncludedLookup[jobID] == true
end

function JobManager:AcceptJob(player: Player, contractID: string): boolean
	if activeJobs[player.UserId] then reject(player, "Finish or quit your current job first.", contractID); return false end
	local contract, includedJobIDs, isCombo = getContract(contractID)
	if contract == nil or includedJobIDs == nil then reject(player, "That contract does not exist.", contractID); return false end
	if TEMP_UNLOCKED_JOBS[contractID] ~= true and not hasUnlockedTier(player, contract.RequiredTier) then
		reject(player, "Complete the previous job tier to unlock " .. contract.DisplayName .. ".", contractID)
		return false
	end
	if not contractAvailable(includedJobIDs) then
		reject(player, contract.DisplayName .. " is coming soon; one of its job sites is not ready yet.", contractID)
		return false
	end

	local includedLookup: {[string]: boolean} = {}
	local perSegments: {[string]: number} = {}
	local perTotalSegments: {[string]: number} = {}
	local perCoverage: {[string]: number} = {}
	local perTotalCoverage: {[string]: number} = {}
	local totalSegments, totalCoverage = 0, 0
	for _, includedID in includedJobIDs do
		includedLookup[includedID] = true
		local template = JOBS[includedID]
		local count, coverage = getRuntimeSegmentStats(includedID, template and template.TotalSegments or 1)
		perSegments[includedID] = 0
		perTotalSegments[includedID] = count
		perCoverage[includedID] = 0
		perTotalCoverage[includedID] = coverage
		totalSegments += count
		totalCoverage += coverage
	end
	local activeJob: ActiveJobData = {
		JobID = contractID,
		DisplayName = contract.DisplayName,
		IsCombo = isCombo,
		IncludedJobIDs = includedJobIDs,
		IncludedLookup = includedLookup,
		CurrentTargetJobID = includedJobIDs[1],
		SegmentsCleaned = 0,
		TotalSegments = totalSegments,
		CleanedCoverage = 0,
		TotalCoverage = totalCoverage,
		PerJobSegmentsCleaned = perSegments,
		PerJobTotalSegments = perTotalSegments,
		PerJobCleanedCoverage = perCoverage,
		PerJobTotalCoverage = perTotalCoverage,
		CleanedInstances = {},
		CleanedLookup = {},
		WaterSource = "PlayerSupplied",
		RewardMultiplier = 1,
		BaseReward = contract.Reward,
	}
	activeJobs[player.UserId] = activeJob
	JobStateChanged:FireClient(player, makeState(activeJob, "Active"))
	return true
end

function JobManager:UseCustomerWater(player: Player, payCut: number): boolean
	local activeJob = activeJobs[player.UserId]
	if activeJob == nil then return false end
	activeJob.WaterSource = "Customer"
	activeJob.RewardMultiplier = math.min(activeJob.RewardMultiplier, math.clamp(1 - payCut, 0, 1))
	JobStateChanged:FireClient(player, makeState(activeJob, "WaterSourceChanged"))
	return true
end

function JobManager:HasCleanedSegment(player: Player, segment: Instance): boolean
	local activeJob = activeJobs[player.UserId]
	return activeJob ~= nil and activeJob.CleanedLookup[segment] == true
end

function JobManager:RecordCleanedSegment(player: Player, segment: Instance): JobTemplate?
	local activeJob = activeJobs[player.UserId]
	if activeJob == nil or activeJob.CleanedLookup[segment] then return nil end
	local segmentJobID = segment:GetAttribute("JobID")
	if typeof(segmentJobID) ~= "string" or not activeJob.IncludedLookup[segmentJobID] then return nil end
	local segmentJob = JOBS[segmentJobID]
	if segmentJob == nil then return nil end

	local previousTarget = activeJob.CurrentTargetJobID
	local weight = getSegmentWeight(segment)
	table.insert(activeJob.CleanedInstances, segment)
	activeJob.CleanedLookup[segment] = true
	activeJob.SegmentsCleaned += 1
	activeJob.CleanedCoverage += weight
	activeJob.PerJobSegmentsCleaned[segmentJobID] = (activeJob.PerJobSegmentsCleaned[segmentJobID] or 0) + 1
	activeJob.PerJobCleanedCoverage[segmentJobID] = (activeJob.PerJobCleanedCoverage[segmentJobID] or 0) + weight
	activeJob.CurrentTargetJobID = getNextTarget(activeJob)

	if allTargetsComplete(activeJob) then
		activeJobs[player.UserId] = nil
		local adjustedBaseReward = math.floor(activeJob.BaseReward * activeJob.RewardMultiplier)
		local awardedReward = self:GetRewardWithPetMultiplier(player, adjustedBaseReward)
		if not DataManager:AddEarnedCash(player, awardedReward) then awardedReward = 0 end
		local newlyUnlockedTier: string? = nil
		if not activeJob.IsCombo then
			local nextTier = NEXT_TIER_BY_JOB[activeJob.JobID]
			if nextTier and not hasUnlockedTier(player, nextTier) and DataManager:UnlockJobTier(player, nextTier) then newlyUnlockedTier = nextTier end
		end
		local completedState = makeState(activeJob, "Completed")
		completedState.Reward = awardedReward
		completedState.BaseReward = adjustedBaseReward
		completedState.CompletionThreshold = JOB_COMPLETION_RATIO * 100
		completedState.NewTierUnlocked = newlyUnlockedTier
		JobStateChanged:FireClient(player, completedState)
		sendCatalogState(player)
		return segmentJob
	end

	local progressState = makeState(activeJob, "Progress")
	progressState.TargetChanged = previousTarget ~= activeJob.CurrentTargetJobID
	JobStateChanged:FireClient(player, progressState)
	return nil
end

function JobManager:QuitJob(player: Player): boolean
	if activeJobs[player.UserId] == nil then reject(player, "You do not have an active job to quit."); return false end
	activeJobs[player.UserId] = nil
	local paid = DataManager:DeductCash(player, 50)
	JobStateChanged:FireClient(player, {
		State = "Quit",
		Penalty = if paid then 50 else 0,
		Message = if paid then "Contract quit. $50 penalty paid." else "Contract quit. No cash was available for the penalty.",
	})
	return true
end

function JobManager:GetRewardWithPetMultiplier(player: Player, baseReward: number): number
	local data = DataManager:GetData(player)
	local pet = data and data.EquippedPet and SharedPetData.Pets[data.EquippedPet]
	return if pet then math.floor(baseReward * pet.CashMult) else baseReward
end

function JobManager:Init()
	if initialized then return end
	initialized = true
	AcceptJobRequest.OnServerEvent:Connect(function(player, jobID)
		if typeof(jobID) == "string" then self:AcceptJob(player, jobID) end
	end)
	QuitJobRequest.OnServerEvent:Connect(function(player) self:QuitJob(player) end)
	JobStateRequest.OnServerEvent:Connect(function(player)
		task.spawn(function()
			for _ = 1, 100 do
				if DataManager:GetData(player) then sendCatalogState(player); return end
				task.wait(0.1)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player) activeJobs[player.UserId] = nil end)
end

return JobManager
