--!strict

-- Server authority for completed client-side dirt segments. The client may
-- render cleaning immediately, but only this module spends water and makes a
-- replicated segment permanently clean.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local JobManager = require(script.Parent:WaitForChild("JobManager"))
local MonetizationManager = require(script.Parent:WaitForChild("MonetizationManager"))

local DIRT_TAG = "DirtSegment"
local MAX_CLEAN_DISTANCE = 20
local BASE_MAX_WATER = 100
local DEFAULT_CLEAN_SPEED = 0.5
local TARGET_EMPTY_DURATION = 30
-- A full segment takes 1 / CleanSpeed seconds. At 0.5, that is two seconds;
-- 100 / 30 * 2 = 6.666... water per completed segment.
local WATER_PER_SEGMENT = BASE_MAX_WATER / (TARGET_EMPTY_DURATION * DEFAULT_CLEAN_SPEED)

local CleanSegmentRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CleanSegmentRequest") :: RemoteEvent

local WasherServer = {}
local initialized = false

local function getWorldPosition(segment: Instance): Vector3?
	if segment:IsA("BasePart") then
		return segment.Position
	end

	if segment:IsA("Decal") and segment.Parent ~= nil and segment.Parent:IsA("BasePart") then
		return segment.Parent.Position
	end

	return nil
end

local function isValidCleaningRequest(player: Player, segment: Instance): boolean
	if not segment:IsDescendantOf(workspace) or not CollectionService:HasTag(segment, DIRT_TAG) then
		return false
	end

	local activeJob = JobManager:GetActiveJob(player)
	if activeJob == nil or JobManager:HasCleanedSegment(player, segment) then
		return false
	end

	-- JobID is authored on the server's segment model. It prevents a player
	-- with an active job from claiming dirt belonging to a different job.
	if segment:GetAttribute("JobID") ~= activeJob.JobID then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end

	local segmentPosition = getWorldPosition(segment)
	if segmentPosition == nil or (root.Position - segmentPosition).Magnitude > MAX_CLEAN_DISTANCE then
		return false
	end

	if character:FindFirstChildOfClass("Tool") == nil then
		return false
	end

	local data = DataManager:GetData(player)
	if data == nil then
		return false
	end

	if not MonetizationManager:OwnsInfiniteWater(player) and data.Water < WATER_PER_SEGMENT then
		return false
	end

	return true
end

local function cleanSegment(player: Player, segment: Instance)
	if not isValidCleaningRequest(player, segment) then
		return
	end

	if not MonetizationManager:OwnsInfiniteWater(player) and not DataManager:DeductWater(player, WATER_PER_SEGMENT) then
		return
	end

	local completedJob = JobManager:RecordCleanedSegment(player, segment)
	if completedJob ~= nil then
		DataManager:AddCash(player, JobManager:GetRewardWithPetMultiplier(player, completedJob.Reward))
	end
end

function WasherServer:Init()
	if initialized then
		return
	end
	initialized = true

	CleanSegmentRequest.OnServerEvent:Connect(function(player, segment)
		if typeof(segment) ~= "Instance" then
			return
		end

		cleanSegment(player, segment)
	end)
end

return WasherServer
