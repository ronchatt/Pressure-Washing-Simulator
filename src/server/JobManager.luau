--!strict

-- Server-authoritative job assignment and per-player cleaning progress.
-- Workspace dirt is never mutated here: each player owns an independent list
-- of segments they have completed for their currently active job.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local SharedJobData = require(ReplicatedStorage.Shared.SharedJobData)
local SharedPetData = require(ReplicatedStorage.Shared.SharedPetData)

export type JobTemplate = SharedJobData.JobTemplate

export type ActiveJobData = {
	JobID: string,
	SegmentsCleaned: number,
	CleanedInstances: {Instance},
}

local JOBS: {[string]: JobTemplate} = SharedJobData.Jobs

local AcceptJobRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AcceptJobRequest") :: RemoteEvent
local QuitJobRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("QuitJobRequest") :: RemoteEvent
local JobStateChanged = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("JobStateChanged") :: RemoteEvent

local JobManager = {}
local activeJobs: {[number]: ActiveJobData} = {}
local initialized = false

local function hasUnlockedTier(player: Player, requiredTier: string): boolean
	local data = DataManager:GetData(player)
	if data == nil then
		return false
	end

	for _, tier in data.UnlockedJobTiers do
		if tier == requiredTier then
			return true
		end
	end

	return false
end

function JobManager:GetJobTemplate(jobID: string): JobTemplate?
	return JOBS[jobID]
end

function JobManager:GetActiveJob(player: Player): ActiveJobData?
	return activeJobs[player.UserId]
end

function JobManager:AcceptJob(player: Player, jobID: string): boolean
	if activeJobs[player.UserId] ~= nil then
		return false
	end

	local job = JOBS[jobID]
	if job == nil or not hasUnlockedTier(player, job.RequiredTier) then
		return false
	end

	activeJobs[player.UserId] = {
		JobID = job.JobID,
		SegmentsCleaned = 0,
		CleanedInstances = {},
	}
	JobStateChanged:FireClient(player, {
		State = "Active",
		JobID = job.JobID,
		SegmentsCleaned = 0,
		TotalSegments = job.TotalSegments,
	})
	return true
end

function JobManager:HasCleanedSegment(player: Player, segment: Instance): boolean
	local activeJob = activeJobs[player.UserId]
	if activeJob == nil then
		return false
	end

	for _, cleanedSegment in activeJob.CleanedInstances do
		if cleanedSegment == segment then
			return true
		end
	end

	return false
end

function JobManager:RecordCleanedSegment(player: Player, segment: Instance): JobTemplate?
	local activeJob = activeJobs[player.UserId]
	if activeJob == nil or self:HasCleanedSegment(player, segment) then
		return nil
	end

	local job = JOBS[activeJob.JobID]
	if job == nil then
		activeJobs[player.UserId] = nil
		return nil
	end

	table.insert(activeJob.CleanedInstances, segment)
	activeJob.SegmentsCleaned += 1

	if activeJob.SegmentsCleaned >= job.TotalSegments then
		activeJobs[player.UserId] = nil
		JobStateChanged:FireClient(player, {
			State = "Completed",
			JobID = job.JobID,
			SegmentsCleaned = job.TotalSegments,
			TotalSegments = job.TotalSegments,
			Reward = job.Reward,
		})
		return job
	end

	JobStateChanged:FireClient(player, {
		State = "Progress",
		JobID = job.JobID,
		SegmentsCleaned = activeJob.SegmentsCleaned,
		TotalSegments = job.TotalSegments,
	})

	return nil
end

function JobManager:QuitJob(player: Player): boolean
	if activeJobs[player.UserId] == nil then
		return false
	end

	activeJobs[player.UserId] = nil
	DataManager:DeductCash(player, 50)
	JobStateChanged:FireClient(player, { State = "Quit" })
	return true
end

function JobManager:GetRewardWithPetMultiplier(player: Player, baseReward: number): number
	local data = DataManager:GetData(player)
	local pet = data and data.EquippedPet and SharedPetData.Pets[data.EquippedPet]
	if pet == nil then
		return baseReward
	end

	return math.floor(baseReward * pet.CashMult)
end

function JobManager:Init()
	if initialized then
		return
	end
	initialized = true

	AcceptJobRequest.OnServerEvent:Connect(function(player, jobID)
		if typeof(jobID) == "string" then
			self:AcceptJob(player, jobID)
		end
	end)

	QuitJobRequest.OnServerEvent:Connect(function(player)
		self:QuitJob(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		activeJobs[player.UserId] = nil
	end)
end

return JobManager
