--!strict

-- Server authority for completed client-side dirt segments. The client may
-- render cleaning immediately, but only this module spends water and makes a
-- replicated segment permanently clean.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local JobManager = require(script.Parent:WaitForChild("JobManager"))
local MonetizationManager = require(script.Parent:WaitForChild("MonetizationManager"))

local DIRT_TAG = "DirtSegment"
-- Matches the client's 90-stud falloff range with a small allowance for the
-- distance between HumanoidRootPart and the equipped nozzle.
local MAX_CLEAN_DISTANCE = 95
local TARGET_EMPTY_DURATION = 30
local WATER_REPORT_INTERVAL = 0.25
local HYDRANT_REFILL_AMOUNT = 100

local CleanSegmentRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CleanSegmentRequest") :: RemoteEvent
local SprayWaterRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SprayWaterRequest") :: RemoteEvent

local WasherServer = {}
local initialized = false
local lastWaterReport: {[Player]: number} = {}
local recentValidSpray: {[Player]: {JobID: string, Timestamp: number}} = {}

local function getWorldPosition(segment: Instance): Vector3?
	if segment:IsA("BasePart") then
		return segment.Position
	end

	if segment:IsA("Decal") and segment.Parent ~= nil and segment.Parent:IsA("BasePart") then
		return segment.Parent.Position
	end

	-- Pixel dirt is represented by GuiObjects under a SurfaceGui. Walk up to
	-- the replicated driveway part for distance validation.
	local ancestor = segment.Parent
	while ancestor do
		if ancestor:IsA("BasePart") then
			return ancestor.Position
		end
		ancestor = ancestor.Parent
	end

	return nil
end

local function isValidCleaningRequest(player: Player, segment: Instance): boolean
	if not segment:IsDescendantOf(Workspace) or not CollectionService:HasTag(segment, DIRT_TAG) then
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

	if not MonetizationManager:OwnsInfiniteWater(player) and data.Water <= 0 then
		return false
	end

	return true
end

local function cleanSegment(player: Player, segment: Instance)
	if not isValidCleaningRequest(player, segment) then
		return
	end

	local recentSpray = recentValidSpray[player]
	if recentSpray == nil
		or recentSpray.JobID ~= segment:GetAttribute("JobID")
		or os.clock() - recentSpray.Timestamp > 0.75
	then
		return
	end

	local completedJob = JobManager:RecordCleanedSegment(player, segment)
	if completedJob ~= nil then
		DataManager:AddCash(player, JobManager:GetRewardWithPetMultiplier(player, completedJob.Reward))
	end
end

local function consumeSprayWater(player: Player, segment: Instance?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") or character:FindFirstChildOfClass("Tool") == nil then
		return
	end

	local data = DataManager:GetData(player)
	if data == nil or data.Water <= 0 then
		return
	end

	local now = os.clock()
	local previousReport = lastWaterReport[player]
	local elapsed = previousReport and now - previousReport or WATER_REPORT_INTERVAL
	if previousReport ~= nil and elapsed < WATER_REPORT_INTERVAL * 0.6 then
		return
	end

	lastWaterReport[player] = now
	-- A valid dirt target authorizes the later completion report. Water itself
	-- is consumed whenever the equipped washer is spraying, including into air.
	if segment ~= nil and isValidCleaningRequest(player, segment) then
		local jobID = segment:GetAttribute("JobID")
		if typeof(jobID) == "string" then
			recentValidSpray[player] = { JobID = jobID, Timestamp = now }
		end
	end

	if MonetizationManager:OwnsInfiniteWater(player) then
		return
	end

	local waterPerSecond = data.MaxWater / TARGET_EMPTY_DURATION
	DataManager:DeductWater(player, waterPerSecond * WATER_REPORT_INTERVAL)
end

local function connectHydrantRefill()
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local base = environment and environment:FindFirstChild("Base")
	local hydrant = base and base:FindFirstChild("FireHydrant")
	local prompt = hydrant and hydrant:FindFirstChild("HydrantRefillPrompt", true)
	if prompt == nil or not prompt:IsA("ProximityPrompt") then
		warn("WasherServer could not find EnvironmentFixtures.Base.FireHydrant.HydrantRefillPrompt")
		return
	end

	prompt.Triggered:Connect(function(player)
		if DataManager:RefillWater(player, HYDRANT_REFILL_AMOUNT) then
			print(string.format("DIAGNOSTIC: Refilled %s's water to %d at the fire hydrant.", player.Name, HYDRANT_REFILL_AMOUNT))
		end
	end)
end

function WasherServer:Init()
	if initialized then
		return
	end
	initialized = true
	connectHydrantRefill()

	CleanSegmentRequest.OnServerEvent:Connect(function(player, segment)
		if typeof(segment) == "Instance" then
			cleanSegment(player, segment)
		elseif typeof(segment) == "table" then
			-- Clients batch nearby coverage cells to avoid losing progress to a
			-- burst of individual RemoteEvents. Every cell is still validated.
			for index = 1, math.min(#segment, 1024) do
				local claimedSegment = segment[index]
				if typeof(claimedSegment) == "Instance" then
					cleanSegment(player, claimedSegment)
				end
			end
		end
	end)

	SprayWaterRequest.OnServerEvent:Connect(function(player, segment)
		if segment ~= nil and typeof(segment) ~= "Instance" then
			return
		end

		consumeSprayWater(player, segment)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastWaterReport[player] = nil
		recentValidSpray[player] = nil
	end)
end

return WasherServer
