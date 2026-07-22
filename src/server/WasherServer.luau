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
local MAX_CLEAN_DISTANCE = 34
local MAX_UPWARD_HOUSE_REACH = 7
local LINE_OF_SIGHT_TOLERANCE = 1.25
local LINE_OF_SIGHT_OVERSHOOT = 2
local BASE_WATER_PER_SECOND = 100 / 30
local WATER_REPORT_INTERVAL = 0.25
local SPRAY_AUTHORIZATION_WINDOW = 0.9
local MAX_CLEAN_REQUESTS_PER_SECOND = 20
local MAX_SEGMENTS_PER_REQUEST = 96
local BASE_COVERAGE_PER_SECOND = 5
local COVERAGE_FRACTION_PER_SECOND = 0.015
local COVERAGE_BURST_SECONDS = 0.6
local MINIMUM_BURST_COVERAGE = 12
local SUSPICION_WARNING_THRESHOLD = 15
local SUSPICION_DECAY_PER_SECOND = 0.2
local SUSPICION_WARNING_COOLDOWN = 10

local CleanSegmentRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CleanSegmentRequest") :: RemoteEvent
local CleanSegmentResult = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CleanSegmentResult") :: RemoteEvent
local SprayWaterRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SprayWaterRequest") :: RemoteEvent

local WasherServer = {}
local initialized = false
local lastWaterReport: {[Player]: number} = {}
type RateBucket = {
	Contract: any,
	Tokens: number,
	LastRefill: number,
}
type RequestWindow = {
	StartedAt: number,
	Count: number,
}
type SuspicionState = {
	Score: number,
	UpdatedAt: number,
	LastWarning: number,
}
local rateBuckets: {[Player]: {[string]: RateBucket}} = {}
local requestWindows: {[Player]: RequestWindow} = {}
local suspicionStates: {[Player]: SuspicionState} = {}

-- Small props have only a few hundred validation regions and high-tier
-- washers legitimately clear many of them in one close sweep. Large surfaces
-- retain tighter limits. This keeps the validator aligned with actual gameplay
-- without giving every job the same overly generous allowance.
local JOB_THROUGHPUT_PROFILES: {[string]: {Multiplier: number, MaxFraction: number, BurstSeconds: number}} = {
	Bench = { Multiplier = 8, MaxFraction = 1, BurstSeconds = 1 },
	Fence = { Multiplier = 6, MaxFraction = 0.8, BurstSeconds = 0.8 },
	Car = { Multiplier = 1.25, MaxFraction = 0.12, BurstSeconds = COVERAGE_BURST_SECONDS },
	Driveway = { Multiplier = 1.35, MaxFraction = 0.55, BurstSeconds = 1.5 },
	House = { Multiplier = 1.25, MaxFraction = 0.12, BurstSeconds = COVERAGE_BURST_SECONDS },
	Mansion = { Multiplier = 1.15, MaxFraction = 0.1, BurstSeconds = COVERAGE_BURST_SECONDS },
}

local DEFAULT_THROUGHPUT_PROFILE = {
	Multiplier = 1,
	MaxFraction = 0.08,
	BurstSeconds = COVERAGE_BURST_SECONDS,
}

local function getJobType(jobID: string): string?
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
	local site = jobSites and jobSites:FindFirstChild(jobID)
	local jobType = site and site:GetAttribute("JobType")
	return if typeof(jobType) == "string" then jobType else nil
end

local function getWasherStats(player: Player)
	local data = DataManager:GetData(player)
	if data then
		return SharedShopData.Washers[data.EquippedWasher] or SharedShopData.Washers["Basic Backpack"]
	end
	return SharedShopData.Washers["Basic Backpack"]
end

local function flagSuspicious(player: Player, reason: string, severity: number)
	local now = os.clock()
	local state = suspicionStates[player]
	if state == nil then
		state = { Score = 0, UpdatedAt = now, LastWarning = 0 }
		suspicionStates[player] = state
	end
	local elapsed = math.max(0, now - state.UpdatedAt)
	state.Score = math.max(0, state.Score - elapsed * SUSPICION_DECAY_PER_SECOND)
		+ math.clamp(severity, 0.25, 10)
	state.UpdatedAt = now
	if state.Score >= SUSPICION_WARNING_THRESHOLD
		and now - state.LastWarning >= SUSPICION_WARNING_COOLDOWN
	then
		state.LastWarning = now
		warn(string.format(
			"SECURITY: rejected suspicious cleaning from %s (%d): %s [score %.1f]",
			player.Name,
			player.UserId,
			reason,
			state.Score
		))
	end
end

local function requestIsWithinLimit(player: Player): boolean
	local now = os.clock()
	local window = requestWindows[player]
	if window == nil or now - window.StartedAt >= 1 then
		requestWindows[player] = { StartedAt = now, Count = 1 }
		return true
	end
	window.Count += 1
	if window.Count > MAX_CLEAN_REQUESTS_PER_SECOND then
		flagSuspicious(player, "too many CleanSegmentRequest events", 2)
		return false
	end
	return true
end

local function getSegmentWeight(segment: Instance): number
	local configuredWeight = segment:GetAttribute("DirtWeight")
	return if typeof(configuredWeight) == "number" and configuredWeight > 0
		then math.clamp(configuredWeight, 0.05, 25)
		else 1
end

local function spendCoverageBudget(player: Player, segment: Instance): boolean
	local activeJob = JobManager:GetActiveJob(player)
	local segmentJobID = segment:GetAttribute("JobID")
	if activeJob == nil or typeof(segmentJobID) ~= "string" then
		return false
	end
	local totalCoverage = activeJob.PerJobTotalCoverage[segmentJobID]
	if typeof(totalCoverage) ~= "number" or totalCoverage <= 0 then
		return false
	end

	local washer = getWasherStats(player)
	local starter = SharedShopData.Washers["Basic Backpack"]
	local powerScale = washer.CleanSpeed / starter.CleanSpeed
	-- Width changes area, so square it. The configured tier widths are already
	-- intentionally compressed and this budget must mirror their real benefit.
	local widthAreaScale = washer.SprayWidth * washer.SprayWidth
	local jobType = getJobType(segmentJobID)
	local profile = (if jobType then JOB_THROUGHPUT_PROFILES[jobType] else nil) or DEFAULT_THROUGHPUT_PROFILE
	local calculatedRate = (BASE_COVERAGE_PER_SECOND + totalCoverage * COVERAGE_FRACTION_PER_SECOND)
		* powerScale
		* widthAreaScale
		* profile.Multiplier
	if jobType == "Driveway" then
		-- Mirrors the client's driveway-only pressure curve. Radius remains
		-- compressed, while upgraded pumps receive substantially more cutting
		-- force and the server accepts that legitimate throughput.
		calculatedRate *= SharedShopData.GetDrivewayPowerScale(washer.CleanSpeed) / powerScale
	end
	local coverageRate = math.min(calculatedRate, totalCoverage * profile.MaxFraction)
	local capacity = math.max(MINIMUM_BURST_COVERAGE, coverageRate * profile.BurstSeconds)
	local playerBuckets = rateBuckets[player]
	if playerBuckets == nil then
		playerBuckets = {}
		rateBuckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[segmentJobID]
	if bucket == nil or bucket.Contract ~= activeJob then
		bucket = { Contract = activeJob, Tokens = capacity, LastRefill = now }
		playerBuckets[segmentJobID] = bucket
	else
		local elapsed = math.max(0, now - bucket.LastRefill)
		bucket.Tokens = math.min(capacity, bucket.Tokens + elapsed * coverageRate)
		bucket.LastRefill = now
	end

	local weight = getSegmentWeight(segment)
	if bucket.Tokens + 0.001 < weight then
		flagSuspicious(player, "cleaning coverage exceeded equipped washer throughput", math.min(weight, 4))
		return false
	end
	bucket.Tokens -= weight
	return true
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

local function getToolNozzle(tool: Tool): BasePart?
	local nozzle = tool:FindFirstChild("Nozzle", true)
	if nozzle ~= nil and nozzle:IsA("BasePart") then return nozzle end
	local handle = tool:FindFirstChild("Handle", true)
	return if handle ~= nil and handle:IsA("BasePart") then handle else nil
end

local function hasNozzleLineOfSight(character: Model, nozzle: BasePart, target: Vector3): boolean
	local offset = target - nozzle.Position
	if offset.Magnitude < 0.01 then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local result = Workspace:Raycast(
		nozzle.Position,
		offset.Unit * (offset.Magnitude + LINE_OF_SIGHT_OVERSHOOT),
		params
	)
	return result ~= nil and (result.Position - target).Magnitude <= LINE_OF_SIGHT_TOLERANCE
end

local function isUpwardHouseSurfaceOutOfReach(segment: Instance, jobType: string?, nozzle: BasePart): boolean
	if jobType ~= "House" and jobType ~= "Mansion" then return false end
	if not segment:IsA("BasePart") then return false end
	-- Dirt patches are authored with their local X axis pointing along the
	-- outward surface normal.
	local surfaceNormal = segment.CFrame.RightVector
	return surfaceNormal.Y > 0.35 and segment.Position.Y - nozzle.Position.Y > MAX_UPWARD_HOUSE_REACH
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

	local data = DataManager:GetData(player)
	if data == nil then
		return false
	end
	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool == nil
		or equippedTool.Name ~= data.EquippedWasher
		or equippedTool:GetAttribute("IsPressureWasher") ~= true
	then
		return false
	end
	local nozzle = getToolNozzle(equippedTool)
	local segmentPosition = getWorldPosition(segment)
	local washer = getWasherStats(player)
	local segmentJobID = segment:GetAttribute("JobID")
	local jobType = if typeof(segmentJobID) == "string" then getJobType(segmentJobID) else nil
	if nozzle == nil
		or segmentPosition == nil
		or (nozzle.Position - segmentPosition).Magnitude > MAX_CLEAN_DISTANCE * washer.EffectiveRange
		or not hasNozzleLineOfSight(character, nozzle, segmentPosition)
		or isUpwardHouseSurfaceOutOfReach(segment, jobType, nozzle)
	then
		return false
	end

	if not MonetizationManager:OwnsInfiniteWater(player) and data.Water <= 0 then
		return false
	end
	local lastSpray = lastWaterReport[player]
	if lastSpray == nil or os.clock() - lastSpray > SPRAY_AUTHORIZATION_WINDOW then
		return false
	end

	return true
end

local function cleanSegment(player: Player, segment: Instance): boolean
	-- A retry for an already-authorized segment is successful from the client's
	-- perspective. Returning it as rejected would incorrectly repaint clean dirt.
	if JobManager:HasCleanedSegment(player, segment) then
		return true
	end
	if not isValidCleaningRequest(player, segment) then
		return false
	end
	if not spendCoverageBudget(player, segment) then
		return false
	end

	-- Distance, equipped tool, water, active job, and duplicate checks above are
	-- the authoritative validation boundary. Requiring a separate heartbeat to
	-- arrive first caused valid completion cells to be dropped permanently when
	-- two reliable RemoteEvents reached the server in adjacent frames.
	JobManager:RecordCleanedSegment(player, segment)
	return true
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
		if not requestIsWithinLimit(player) then
			if typeof(segment) == "Instance" then
				CleanSegmentResult:FireClient(player, { segment })
			elseif typeof(segment) == "table" then
				local rejected: {Instance} = {}
				for index = 1, math.min(#segment, MAX_SEGMENTS_PER_REQUEST) do
					if typeof(segment[index]) == "Instance" then table.insert(rejected, segment[index]) end
				end
				if #rejected > 0 then CleanSegmentResult:FireClient(player, rejected) end
			end
			return
		end
		if typeof(segment) == "Instance" then
			if not cleanSegment(player, segment) then CleanSegmentResult:FireClient(player, { segment }) end
		elseif typeof(segment) == "table" then
			-- Clients batch nearby coverage cells to avoid losing progress to a
			-- burst of individual RemoteEvents. Every cell is still validated.
			if #segment > MAX_SEGMENTS_PER_REQUEST then
				flagSuspicious(player, "oversized cleaning batch", math.min(#segment / MAX_SEGMENTS_PER_REQUEST, 10))
			end
			local rejected: {Instance} = {}
			for index = 1, math.min(#segment, MAX_SEGMENTS_PER_REQUEST) do
				local claimedSegment = segment[index]
				if typeof(claimedSegment) == "Instance" then
					if not cleanSegment(player, claimedSegment) then
						table.insert(rejected, claimedSegment)
					end
				end
			end
			if #rejected > 0 then CleanSegmentResult:FireClient(player, rejected) end
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
		rateBuckets[player] = nil
		requestWindows[player] = nil
		suspicionStates[player] = nil
	end)
end

return WasherServer
