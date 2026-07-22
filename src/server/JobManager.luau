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
local SharedProgressionData = require(shared:WaitForChild("SharedProgressionData"))

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
	XPReward: number,
}

local JOBS: {[string]: JobTemplate} = {}
local JOB_ORDER: {string} = {}
local COMBO_JOBS = SharedJobData.ComboJobs
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AcceptJobRequest = remotes:WaitForChild("AcceptJobRequest") :: RemoteEvent
local QuitJobRequest = remotes:WaitForChild("QuitJobRequest") :: RemoteEvent
local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent
local JobStateRequest = remotes:WaitForChild("JobStateRequest") :: RemoteEvent

local JobManager = {}
local activeJobs: {[number]: ActiveJobData} = {}
local initialized = false
local DEFAULT_JOB_COMPLETION_RATIO = 0.95
local TEMP_UNLOCKED_JOBS: {[string]: boolean} = { SingleStoryHouse_1 = true }
local assignmentRandom = Random.new()

local function getCompletionRatio(jobID: string): number
	local job = JOBS[jobID]
	return if job then math.clamp(job.CompletionThreshold / 100, 0.5, 1) else DEFAULT_JOB_COMPLETION_RATIO
end

local function getJobSitesFolder(): Folder?
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local sites = environment and environment:FindFirstChild("JobSites")
	return if sites and sites:IsA("Folder") then sites else nil
end

local function attributeOrDefault(site: Instance, name: string, fallback: any): any
	local value = site:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function refreshRuntimeCatalog()
	table.clear(JOBS)
	table.clear(JOB_ORDER)
	for _, jobID in SharedJobData.JobOrder do
		local template = SharedJobData.Jobs[jobID]
		if template then
			JOBS[jobID] = table.clone(template)
			table.insert(JOB_ORDER, jobID)
		end
	end

	local sites = getJobSitesFolder()
	if sites == nil then return end
	local extras: {string} = {}
	for _, site in sites:GetChildren() do
		local jobID = site:GetAttribute("JobID")
		local poolID = site:GetAttribute("JobPoolID")
		local isPooled = typeof(poolID) == "string" and poolID ~= ""
		if typeof(jobID) ~= "string" or (site:GetAttribute("PhoneJobEnabled") ~= true and not isPooled) then
			continue
		end
		local fallback = JOBS[jobID] or (isPooled and JOBS[poolID :: string])
		local patchCount = site:GetAttribute("DirtPatchCount")
		local jobType = attributeOrDefault(site, "JobType", fallback and fallback.JobType or "Bench")
		local definition: JobTemplate = {
			JobID = jobID,
			JobType = if typeof(jobType) == "string" then jobType else "Bench",
			DisplayName = tostring(attributeOrDefault(site, "DisplayName", fallback and fallback.DisplayName or jobID)),
			RequiredTier = tostring(attributeOrDefault(site, "RequiredTier", fallback and fallback.RequiredTier or "Benches")),
			Difficulty = tostring(attributeOrDefault(site, "Difficulty", fallback and fallback.Difficulty or "Easy")),
			RecommendedWasher = tostring(attributeOrDefault(site, "RecommendedWasher", fallback and fallback.RecommendedWasher or "Basic Backpack")),
			Reward = math.max(0, tonumber(attributeOrDefault(site, "Reward", fallback and fallback.Reward or 50)) or 50),
			CompletionThreshold = math.clamp(tonumber(attributeOrDefault(site, "CompletionThreshold", fallback and fallback.CompletionThreshold or 95)) or 95, 50, 100),
			TotalSegments = math.max(1, tonumber(patchCount) or (fallback and fallback.TotalSegments) or 1),
			UnlockLevel = math.max(1, tonumber(attributeOrDefault(site, "UnlockLevel", fallback and fallback.UnlockLevel or 1)) or 1),
			XPReward = math.max(0, tonumber(attributeOrDefault(site, "XPReward", fallback and fallback.XPReward or 0)) or 0),
		}
		JOBS[jobID] = definition
		if not isPooled and not table.find(JOB_ORDER, jobID) then table.insert(extras, jobID) end
	end
	table.sort(extras)
	for _, jobID in extras do table.insert(JOB_ORDER, jobID) end
end

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

local function isUsableJobSite(site: Instance?): boolean
	return site ~= nil and site:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function getPooledSiteIDs(poolID: string): {string}
	local sites = getJobSitesFolder()
	if sites == nil then return {} end
	local pooled: {string} = {}
	for _, site in sites:GetChildren() do
		if site:GetAttribute("JobPoolID") == poolID and isUsableJobSite(site) then
			local physicalID = site:GetAttribute("JobID")
			if typeof(physicalID) == "string" then table.insert(pooled, physicalID) end
		end
	end
	table.sort(pooled)
	-- Preserve the original authored site as a fallback while the town is being
	-- built, but prefer the dedicated town pool as soon as it exists.
	if #pooled == 0 then
		local fallback = sites:FindFirstChild(poolID)
		if isUsableJobSite(fallback) then table.insert(pooled, poolID) end
	end
	return pooled
end

local function jobSiteExists(jobID: string): boolean
	return #getPooledSiteIDs(jobID) > 0
end

local function getSiteOccupancy(siteID: string): number
	local count = 0
	for _, activeJob in activeJobs do
		if activeJob.IncludedLookup[siteID] then count += 1 end
	end
	return count
end

local function choosePhysicalSite(poolID: string): string?
	local candidates = getPooledSiteIDs(poolID)
	if #candidates == 0 then return nil end
	local leastOccupied = math.huge
	local best: {string} = {}
	for _, siteID in candidates do
		local occupancy = getSiteOccupancy(siteID)
		if occupancy < leastOccupied then
			leastOccupied = occupancy
			table.clear(best)
			table.insert(best, siteID)
		elseif occupancy == leastOccupied then
			table.insert(best, siteID)
		end
	end
	return best[assignmentRandom:NextInteger(1, #best)]
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
		if (activeJob.PerJobCleanedCoverage[jobID] or 0) < total * getCompletionRatio(jobID) then
			return jobID
		end
	end
	return nil
end

local function allTargetsComplete(activeJob: ActiveJobData): boolean
	return getNextTarget(activeJob) == nil
end

local function sendCatalogState(player: Player)
	refreshRuntimeCatalog()
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
		JobDefinitions = JOBS,
		JobOrder = JOB_ORDER,
		ActiveJobID = activeJob and activeJob.JobID or nil,
		Level = data.Level,
		XP = data.XP,
		XPToNextLevel = SharedProgressionData.GetXPToNextLevel(data.XP),
		TotalJobsCompleted = data.TotalJobsCompleted,
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
		XPReward = activeJob.XPReward,
	}
end

function JobManager:GetJobTemplate(jobID: string): JobTemplate?
	refreshRuntimeCatalog()
	return JOBS[jobID]
end

function JobManager:GetJobIDs(): {string}
	refreshRuntimeCatalog()
	return table.clone(JOB_ORDER)
end

function JobManager:GetActiveJob(player: Player): ActiveJobData?
	return activeJobs[player.UserId]
end

function JobManager:IsJobPartOfActive(player: Player, jobID: string): boolean
	local activeJob = activeJobs[player.UserId]
	return activeJob ~= nil and activeJob.IncludedLookup[jobID] == true
end

function JobManager:AcceptJob(player: Player, contractID: string): boolean
	refreshRuntimeCatalog()
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
	local physicalJobIDs: {string} = {}
	for _, logicalJobID in includedJobIDs do
		local physicalJobID = choosePhysicalSite(logicalJobID)
		if physicalJobID == nil then
			reject(player, contract.DisplayName .. " has no available physical site.", contractID)
			return false
		end
		table.insert(physicalJobIDs, physicalJobID)
	end
	includedJobIDs = physicalJobIDs

	local includedLookup: {[string]: boolean} = {}
	local perSegments: {[string]: number} = {}
	local perTotalSegments: {[string]: number} = {}
	local perCoverage: {[string]: number} = {}
	local perTotalCoverage: {[string]: number} = {}
	local totalSegments, totalCoverage = 0, 0
	local totalXPReward = 0
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
		totalXPReward += template and template.XPReward or 0
	end
	if isCombo then totalXPReward = math.floor(totalXPReward * 1.1) end
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
		XPReward = totalXPReward,
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
		local progressionResult = DataManager:RecordJobCompletion(player, activeJob.JobID, activeJob.XPReward)
		local completedState = makeState(activeJob, "Completed")
		completedState.Reward = awardedReward
		completedState.BaseReward = adjustedBaseReward
		if not activeJob.IsCombo then
			completedState.CompletionThreshold = getCompletionRatio(activeJob.JobID) * 100
		end
		if progressionResult then
			completedState.XP = progressionResult.XP
			completedState.Level = progressionResult.Level
			completedState.PreviousLevel = progressionResult.PreviousLevel
			completedState.LeveledUp = progressionResult.LeveledUp
			completedState.XPToNextLevel = progressionResult.XPToNextLevel
			completedState.TotalJobsCompleted = progressionResult.TotalJobsCompleted
			completedState.NewlyUnlockedTiers = progressionResult.NewlyUnlockedTiers
			completedState.NewTierUnlocked = progressionResult.NewlyUnlockedTiers[1]
		end
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
	local multiplier = player:GetAttribute("PetCashMultiplier")
	local safeMultiplier = if typeof(multiplier) == "number" then math.clamp(multiplier, 1, 10) else 1
	return math.floor(baseReward * safeMultiplier)
end

function JobManager:Init()
	if initialized then return end
	initialized = true
	refreshRuntimeCatalog()
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
