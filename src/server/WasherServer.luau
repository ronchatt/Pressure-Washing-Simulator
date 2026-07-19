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
local SharedShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedShopData"))

local DIRT_TAG = "DirtSegment"
-- Matches the client's 90-stud falloff range with a small allowance for the
-- distance between HumanoidRootPart and the equipped nozzle.
local MAX_CLEAN_DISTANCE = 95
local BASE_WATER_PER_SECOND = 100 / 30
local WATER_REPORT_INTERVAL = 0.25

local CleanSegmentRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CleanSegmentRequest") :: RemoteEvent
local SprayWaterRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SprayWaterRequest") :: RemoteEvent

local WasherServer = {}
local initialized = false
local lastWaterReport: {[Player]: number} = {}

local function getWasherStats(player: Player)
	local data = DataManager:GetData(player)
	if data then
		return SharedShopData.Washers[data.EquippedWasher] or SharedShopData.Washers["Basic Backpack"]
	end
	return SharedShopData.Washers["Basic Backpack"]
end

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
	local segmentJobID = segment:GetAttribute("JobID")
	if typeof(segmentJobID) ~= "string" or not JobManager:IsJobPartOfActive(player, segmentJobID) then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end

	local segmentPosition = getWorldPosition(segment)
	local washer = getWasherStats(player)
	if segmentPosition == nil or (root.Position - segmentPosition).Magnitude > MAX_CLEAN_DISTANCE * washer.EffectiveRange then
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

	-- Distance, equipped tool, water, active job, and duplicate checks above are
	-- the authoritative validation boundary. Requiring a separate heartbeat to
	-- arrive first caused valid completion cells to be dropped permanently when
	-- two reliable RemoteEvents reached the server in adjacent frames.
	JobManager:RecordCleanedSegment(player, segment)
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
	if MonetizationManager:OwnsInfiniteWater(player) then
		return
	end

	local washer = getWasherStats(player)
	local waterPerSecond = BASE_WATER_PER_SECOND / washer.WaterEfficiency
	DataManager:DeductWater(player, waterPerSecond * WATER_REPORT_INTERVAL)
end

local function getObjectBounds(object: Instance): (CFrame?, Vector3?)
	if object:IsA("Model") then
		return object:GetBoundingBox()
	elseif object:IsA("BasePart") then
		return object.CFrame, object.Size
	end
	return nil, nil
end

local function placeHydrantNearJobs(hydrant: Model | BasePart)
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
	local bench = jobSites and jobSites:FindFirstChild("Bench_1")
	local fence = jobSites and jobSites:FindFirstChild("Fence_1")
	local benchCFrame = bench and select(1, getObjectBounds(bench))
	local fenceCFrame = fence and select(1, getObjectBounds(fence))
	if benchCFrame == nil and fenceCFrame == nil then
		warn("WasherServer could not position the hydrant because Bench_1 and Fence_1 are unavailable")
		return
	end

	local center: Vector3
	local outward: Vector3
	if benchCFrame ~= nil and fenceCFrame ~= nil then
		center = (benchCFrame.Position + fenceCFrame.Position) * 0.5
		local between = fenceCFrame.Position - benchCFrame.Position
		local flatBetween = Vector3.new(between.X, 0, between.Z)
		outward = if flatBetween.Magnitude > 0.1
			then Vector3.new(-flatBetween.Z, 0, flatBetween.X).Unit
			else Vector3.xAxis
	else
		local availableCFrame = benchCFrame or fenceCFrame
		center = (availableCFrame :: CFrame).Position
		outward = Vector3.xAxis
	end

	local boundsCFrame, boundsSize = getObjectBounds(hydrant)
	if boundsCFrame == nil or boundsSize == nil then
		return
	end
	local desiredCenter = Vector3.new(center.X, boundsSize.Y * 0.5, center.Z) + outward * 6
	local translation = desiredCenter - boundsCFrame.Position
	hydrant:PivotTo(hydrant:GetPivot() + translation)
end

local function connectHydrantRefill()
	local hydrant = Workspace:FindFirstChild("Fire Hydrant", true)
	if hydrant == nil or (not hydrant:IsA("Model") and not hydrant:IsA("BasePart")) then
		warn("WasherServer could not find a movable Workspace['Fire Hydrant'] Model or BasePart")
		return
	end

	for _, descendant in hydrant:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	if hydrant:IsA("BasePart") then
		hydrant.Anchored = true
	end
	placeHydrantNearJobs(hydrant)

	local promptParent = if hydrant:IsA("BasePart")
		then hydrant
		else hydrant.PrimaryPart or hydrant:FindFirstChildWhichIsA("BasePart", true)
	if promptParent == nil then
		warn("Workspace['Fire Hydrant'] has no BasePart for its refill prompt")
		return
	end
	local existingPrompt = hydrant:FindFirstChild("HydrantRefillPrompt", true)
	local prompt: ProximityPrompt
	if existingPrompt ~= nil and existingPrompt:IsA("ProximityPrompt") then
		prompt = existingPrompt
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HydrantRefillPrompt"
		prompt.Parent = promptParent
	end
	prompt.ActionText = "Refill Water"
	prompt.ObjectText = "Fire Hydrant"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false

	print("WasherServer: moved and linked Workspace['Fire Hydrant'] beside the bench and fence.")
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
	end)
end

return WasherServer
