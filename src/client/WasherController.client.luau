--!strict

-- Client-only spray feedback and dirt visuals. Server validation, water use,
-- and job progress reporting are deliberately added in a later system.

local CollectionService = game:GetService("CollectionService")
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PLAYER = Players.LocalPlayer
local PLAYER_MOUSE = PLAYER:GetMouse()
local DIRT_TAG = "DirtSegment"
local DEFAULT_CLEAN_SPEED = 0.5
local MAX_SPRAY_DISTANCE = 90
local WATER_REPORT_INTERVAL = 0.25
local CLEAN_REPORT_INTERVAL = 0.1
local CLEAN_TWEEN_STEP = 0.1
-- One visual pass should complete the matching invisible coverage cells. The
-- high-resolution alpha mask still controls the satisfying fade itself.
local PIXEL_CLEAN_POWER = 20
local PIXEL_BRUSH_RADIUS = 3
local DIRT_IMAGE_SIZE = Vector2.new(512, 768)
local DIRT_BRUSH_RADIUS = 28
local BASE_WORLD_BRUSH_RADIUS = 0.55
local FULL_PRESSURE_DISTANCE = 12
local PRESSURE_FALLOFF_DISTANCE = 70
local MIN_PRESSURE_MULTIPLIER = 0.2

local washersInstance = ReplicatedStorage:WaitForChild("Washers")
assert(washersInstance:IsA("Folder"), "ReplicatedStorage.Washers must be a Folder")
local Washers = washersInstance :: Folder
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local cleanRequestInstance = remotes:WaitForChild("CleanSegmentRequest")
local sprayRequestInstance = remotes:WaitForChild("SprayWaterRequest")
local jobStateInstance = remotes:WaitForChild("JobStateChanged")
assert(cleanRequestInstance:IsA("RemoteEvent"), "CleanSegmentRequest must be a RemoteEvent")
assert(sprayRequestInstance:IsA("RemoteEvent"), "SprayWaterRequest must be a RemoteEvent")
assert(jobStateInstance:IsA("RemoteEvent"), "JobStateChanged must be a RemoteEvent")
local CleanSegmentRequest = cleanRequestInstance :: RemoteEvent
local SprayWaterRequest = sprayRequestInstance :: RemoteEvent
local JobStateChanged = jobStateInstance :: RemoteEvent
local playerGui = PLAYER:WaitForChild("PlayerGui")
local sprayStateSignal = playerGui:FindFirstChild("WasherSprayStateChanged")
if sprayStateSignal == nil then
	sprayStateSignal = Instance.new("BindableEvent")
	sprayStateSignal.Name = "WasherSprayStateChanged"
	sprayStateSignal.Parent = playerGui
end
local typedSprayStateSignal = sprayStateSignal :: BindableEvent
local activeTool: Tool? = nil
local sprayEmitter: ParticleEmitter? = nil
local waterBeam: Beam? = nil
local waterEndpoint: Part? = nil
local impactEmitter: ParticleEmitter? = nil
local isSpraying = false
local connectedTools = setmetatable({} :: {[Tool]: boolean}, { __mode = "k" })
local activeCleanTweens = setmetatable({} :: {[Instance]: boolean}, { __mode = "k" })
local segmentProgress = setmetatable({} :: {[Instance]: number}, { __mode = "k" })
local originalPartTransparency = setmetatable({} :: {[BasePart]: number}, { __mode = "k" })
local originalGuiTransparency = setmetatable({} :: {[Frame]: number}, { __mode = "k" })
local waterReportAccumulator = 0
local loggedDrivewayTarget = false
local dirtImage: EditableImage? = nil
local dirtDriveway: BasePart? = nil
local dirtPixelBuffer: buffer? = nil
local previousDirtImagePoint: Vector2? = nil
local activeJobID: string? = nil
local pendingCleanSegments: {Instance} = {}
local pendingCleanLookup: {[Instance]: boolean} = {}
local cleanReportAccumulator = 0

local function fillDirtBuffer(pixels: buffer)
	local imageWidth = DIRT_IMAGE_SIZE.X
	local imageHeight = DIRT_IMAGE_SIZE.Y
	for y = 0, imageHeight - 1 do
		for x = 0, imageWidth - 1 do
			local index = (y * imageWidth + x) * 4
			local fineGrime = math.floor(math.noise(x * 0.045, y * 0.045, 3) * 13)
			local stain = math.noise(x * 0.014, y * 0.014, 17)
			local stainVariation = math.noise(x * 0.021, y * 0.021, 41)
			local red: number
			local green: number
			local blue: number
			local dirtAlpha = 246

			if stain > 0.42 then
				-- Damp, yellow-green organic grime.
				red, green, blue = 55 + fineGrime, 58 + fineGrime, 27
				dirtAlpha = 152
			elseif stain < -0.43 then
				-- Bruised purple-black mold patches.
				red, green, blue = 49 + fineGrime, 29, 45 + fineGrime
				dirtAlpha = 170
			elseif stainVariation > 0.46 then
				-- Sparse rusty orange-brown stains.
				red, green, blue = 72 + fineGrime, 38 + math.floor(fineGrime * 0.4), 21
				dirtAlpha = 164
			else
				-- Predominantly charcoal grime with a warm brown undertone.
				red, green, blue = 37 + fineGrime, 32 + math.floor(fineGrime * 0.55), 27
			end

			buffer.writeu8(pixels, index, math.clamp(red, 0, 255))
			buffer.writeu8(pixels, index + 1, math.clamp(green, 0, 255))
			buffer.writeu8(pixels, index + 2, math.clamp(blue, 0, 255))
			buffer.writeu8(pixels, index + 3, dirtAlpha)
		end
	end
end

local function initializeHighResolutionDirt()
	local environment = Workspace:WaitForChild("EnvironmentFixtures", 15)
	local jobSites = environment and environment:WaitForChild("JobSites", 15)
	local benchSite = jobSites and jobSites:WaitForChild("Bench_1", 15)
	local drivewayInstance = benchSite and benchSite:FindFirstChild("Driveway")
	local dirtPixels = benchSite and benchSite:WaitForChild("DirtPixels", 15)
	if drivewayInstance == nil then
		-- The real Blender bench uses many small surface-aligned dirt patches;
		-- the EditableImage canvas remains the flat-driveway fallback only.
		print("DIAGNOSTIC: Using 3D bench dirt patches instead of the flat EditableImage canvas.")
		return
	end
	if not drivewayInstance:IsA("BasePart") or dirtPixels == nil then
		warn("High-resolution dirt mask found an invalid development driveway.")
		return
	end

	local success, editableResult = pcall(function()
		return AssetService:CreateEditableImage({ Size = DIRT_IMAGE_SIZE })
	end)
	if not success or editableResult == nil then
		warn("High-resolution dirt mask unavailable; using physical dirt pixels instead.", editableResult)
		return
	end

	local editable = editableResult :: EditableImage
	local imageWidth = DIRT_IMAGE_SIZE.X
	local imageHeight = DIRT_IMAGE_SIZE.Y
	local pixels = buffer.create(imageWidth * imageHeight * 4)
	fillDirtBuffer(pixels)
	editable:WritePixelsBuffer(Vector2.zero, DIRT_IMAGE_SIZE, pixels)

	-- A dedicated front-facing canvas gives us an explicit coordinate system.
	-- SurfaceGui orientation on a Part's Top face is mirrored relative to world
	-- dirt coordinates, which caused the visual cleaning offset.
	local canvasPart = Instance.new("Part")
	canvasPart.Name = "LocalDirtCanvas"
	canvasPart.Size = Vector3.new(drivewayInstance.Size.X, drivewayInstance.Size.Z, 0.02)
	canvasPart.CFrame = drivewayInstance.CFrame
		* CFrame.new(0, drivewayInstance.Size.Y * 0.5 + 0.025, 0)
		* CFrame.Angles(math.rad(-90), 0, 0)
	canvasPart.Anchored = true
	canvasPart.CanCollide = false
	canvasPart.CanQuery = false
	canvasPart.CanTouch = false
	canvasPart.CastShadow = false
	canvasPart.Transparency = 1
	canvasPart.Parent = Workspace

	local surface = Instance.new("SurfaceGui")
	surface.Name = "LocalHighResolutionDirt"
	surface.Face = Enum.NormalId.Back
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = DIRT_IMAGE_SIZE
	surface.LightInfluence = 0.35
	surface.AlwaysOnTop = false
	surface.Parent = canvasPart

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "DirtImage"
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.BackgroundTransparency = 1
	imageLabel.ImageContent = Content.fromObject(editable)
	imageLabel.Parent = surface

	-- Preserve the logical server segments for validation while rendering the
	-- much finer EditableImage locally.
	for _, pixel in dirtPixels:GetChildren() do
		if pixel:IsA("BasePart") then
			pixel.LocalTransparencyModifier = 1
		end
	end

	dirtImage = editable
	dirtDriveway = drivewayInstance
	dirtPixelBuffer = pixels
	print("DIAGNOSTIC: High-resolution 512x768 dirt mask is active.")
end

local function resetJobDirt(jobID: string)
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
	local site = jobSites and jobSites:FindFirstChild(jobID)
	if site ~= nil then
		for _, descendant in site:GetDescendants() do
			if descendant:IsA("BasePart") and descendant:GetAttribute("DirtPixel") == true then
				local originalTransparency = descendant:GetAttribute("OriginalTransparency")
				if typeof(originalTransparency) == "number" then
					descendant.Transparency = originalTransparency
				end
				descendant.CanQuery = true
				segmentProgress[descendant] = nil
				activeCleanTweens[descendant] = nil
				if not CollectionService:HasTag(descendant, DIRT_TAG) then
					CollectionService:AddTag(descendant, DIRT_TAG)
				end
			end
		end
	end

	if jobID == "Bench_1" and dirtImage ~= nil and dirtPixelBuffer ~= nil then
		fillDirtBuffer(dirtPixelBuffer)
		dirtImage:WritePixelsBuffer(Vector2.zero, DIRT_IMAGE_SIZE, dirtPixelBuffer)
	end
	previousDirtImagePoint = nil
end

JobStateChanged.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then
		return
	end

	if state.State == "Active" and typeof(state.JobID) == "string" then
		pendingCleanSegments = {}
		pendingCleanLookup = {}
		activeJobID = state.JobID
		resetJobDirt(state.JobID)
	elseif state.State == "Quit" then
		pendingCleanSegments = {}
		pendingCleanLookup = {}
		local previousJobID = activeJobID
		activeJobID = nil
		if previousJobID ~= nil then
			resetJobDirt(previousJobID)
		end
	elseif state.State == "Completed" then
		pendingCleanSegments = {}
		pendingCleanLookup = {}
		activeJobID = nil
		previousDirtImagePoint = nil
	end
end)

local function distanceToStroke(point: Vector2, strokeStart: Vector2, strokeEnd: Vector2): number
	local stroke = strokeEnd - strokeStart
	local lengthSquared = stroke:Dot(stroke)
	if lengthSquared < 0.001 then
		return (point - strokeStart).Magnitude
	end
	local alpha = math.clamp((point - strokeStart):Dot(stroke) / lengthSquared, 0, 1)
	return (point - strokeStart:Lerp(strokeEnd, alpha)).Magnitude
end

local function cleanHighResolutionDirt(worldPosition: Vector3, pressureMultiplier: number, brushScale: number)
	local editable = dirtImage
	local driveway = dirtDriveway
	local pixels = dirtPixelBuffer
	if editable == nil or driveway == nil or pixels == nil then
		return
	end

	local localPosition = driveway.CFrame:PointToObjectSpace(worldPosition)
	local u = math.clamp(localPosition.X / driveway.Size.X + 0.5, 0, 1)
	-- Back-face canvas right/down map directly to driveway +X/+Z.
	local v = math.clamp(localPosition.Z / driveway.Size.Z + 0.5, 0, 1)
	local imagePoint = Vector2.new(u * (DIRT_IMAGE_SIZE.X - 1), v * (DIRT_IMAGE_SIZE.Y - 1))
	local previousPoint = previousDirtImagePoint or imagePoint
	local brushRadius = DIRT_BRUSH_RADIUS * brushScale
	local minX = math.max(0, math.floor(math.min(previousPoint.X, imagePoint.X) - brushRadius))
	local minY = math.max(0, math.floor(math.min(previousPoint.Y, imagePoint.Y) - brushRadius))
	local maxX = math.min(DIRT_IMAGE_SIZE.X - 1, math.ceil(math.max(previousPoint.X, imagePoint.X) + brushRadius))
	local maxY = math.min(DIRT_IMAGE_SIZE.Y - 1, math.ceil(math.max(previousPoint.Y, imagePoint.Y) + brushRadius))
	local regionWidth = maxX - minX + 1
	local regionHeight = maxY - minY + 1
	local region = buffer.create(regionWidth * regionHeight * 4)

	for y = minY, maxY do
		for x = minX, maxX do
			local fullIndex = (y * DIRT_IMAGE_SIZE.X + x) * 4
			local distance = distanceToStroke(Vector2.new(x, y), previousPoint, imagePoint)
			if distance <= brushRadius then
				local strength = 1 - distance / brushRadius
				local alpha = buffer.readu8(pixels, fullIndex + 3)
				-- Several frames are required to remove the alpha completely. The
				-- center cleans fastest while the feathered edge dissolves slowly.
				local fadeAmount = math.max(1, math.floor((22 + 50 * strength ^ 0.65) * pressureMultiplier))
				buffer.writeu8(pixels, fullIndex + 3, math.max(0, alpha - fadeAmount))
			end

			local regionIndex = ((y - minY) * regionWidth + (x - minX)) * 4
			buffer.writeu8(region, regionIndex, buffer.readu8(pixels, fullIndex))
			buffer.writeu8(region, regionIndex + 1, buffer.readu8(pixels, fullIndex + 1))
			buffer.writeu8(region, regionIndex + 2, buffer.readu8(pixels, fullIndex + 2))
			buffer.writeu8(region, regionIndex + 3, buffer.readu8(pixels, fullIndex + 3))
		end
	end
	editable:WritePixelsBuffer(Vector2.new(minX, minY), Vector2.new(regionWidth, regionHeight), region)
	previousDirtImagePoint = imagePoint
end

task.spawn(initializeHighResolutionDirt)

local function getCleanSpeed(): number
	local configuredSpeed = PLAYER:GetAttribute("WasherCleanSpeed")
	if typeof(configuredSpeed) == "number" then
		return configuredSpeed
	end

	return DEFAULT_CLEAN_SPEED
end

local function getNozzle(tool: Tool): BasePart?
	local nozzle = tool:FindFirstChild("Nozzle")
	if nozzle ~= nil and nozzle:IsA("BasePart") then
		return nozzle
	end

	local handle = tool:FindFirstChild("Handle") or tool:WaitForChild("Handle", 5)
	if handle ~= nil and handle:IsA("BasePart") then
		return handle
	end

	return nil
end

local function setSprayEnabled(enabled: boolean)
	local wasSpraying = isSpraying
	isSpraying = enabled and activeTool ~= nil
	if sprayEmitter ~= nil then
		sprayEmitter.Enabled = isSpraying
	end
	if waterBeam ~= nil then
		waterBeam.Enabled = isSpraying
	end
	if impactEmitter ~= nil and not isSpraying then
		impactEmitter.Enabled = false
	end
	if wasSpraying ~= isSpraying then
		typedSprayStateSignal:Fire(isSpraying)
	end
	if isSpraying and not wasSpraying then
		-- Authorize the first coverage cells immediately instead of waiting for
		-- the first quarter-second water heartbeat.
		waterReportAccumulator = WATER_REPORT_INTERVAL
	end
	if not isSpraying then
		previousDirtImagePoint = nil
	end
end

local function getPressureMultiplier(distance: number): number
	if distance <= FULL_PRESSURE_DISTANCE then
		return 1
	end
	local falloff = (distance - FULL_PRESSURE_DISTANCE) / PRESSURE_FALLOFF_DISTANCE
	return math.clamp(1 - falloff, MIN_PRESSURE_MULTIPLIER, 1)
end

local function flushCleanReports()
	if #pendingCleanSegments == 0 then
		return
	end
	local batch = pendingCleanSegments
	pendingCleanSegments = {}
	pendingCleanLookup = {}
	CleanSegmentRequest:FireServer(batch)
end

local function clearWaterStream()
	if waterBeam then
		waterBeam:Destroy()
		waterBeam = nil
	end
	if waterEndpoint then
		waterEndpoint:Destroy()
		waterEndpoint = nil
	end
	impactEmitter = nil
end

local function ensureWaterStream(tool: Tool)
	clearWaterStream()
	local nozzle = getNozzle(tool)
	if nozzle == nil then
		return
	end

	local originAttachment = nozzle:FindFirstChild("SprayOrigin")
	if originAttachment == nil or not originAttachment:IsA("Attachment") then
		if originAttachment then
			originAttachment:Destroy()
		end
		originAttachment = Instance.new("Attachment")
		originAttachment.Name = "SprayOrigin"
		originAttachment.Position = Vector3.new(0, 0, -nozzle.Size.Z * 0.5)
		originAttachment.Parent = nozzle
	end

	local endpoint = Instance.new("Part")
	endpoint.Name = "LocalWaterImpact"
	endpoint.Size = Vector3.new(0.15, 0.15, 0.15)
	endpoint.Anchored = true
	endpoint.CanCollide = false
	endpoint.CanQuery = false
	endpoint.CanTouch = false
	endpoint.Transparency = 1
	endpoint.Parent = Workspace
	waterEndpoint = endpoint

	local endpointAttachment = Instance.new("Attachment")
	endpointAttachment.Name = "ImpactAttachment"
	endpointAttachment.Parent = endpoint

	local beam = Instance.new("Beam")
	beam.Name = "PressureWaterStream"
	beam.Attachment0 = originAttachment
	beam.Attachment1 = endpointAttachment
	beam.Enabled = false
	beam.FaceCamera = true
	beam.Width0 = 0.1
	beam.Width1 = 0.22
	beam.LightEmission = 0.85
	beam.Color = ColorSequence.new(Color3.fromRGB(205, 239, 255), Color3.fromRGB(111, 202, 255))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.75, 0.2),
		NumberSequenceKeypoint.new(1, 0.48),
	})
	beam.Parent = nozzle
	waterBeam = beam

	local impact = Instance.new("ParticleEmitter")
	impact.Name = "WaterImpactMist"
	impact.Enabled = false
	impact.Rate = 120
	impact.Lifetime = NumberRange.new(0.08, 0.18)
	impact.Speed = NumberRange.new(3, 7)
	impact.SpreadAngle = Vector2.new(80, 80)
	impact.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0.03),
	})
	impact.Transparency = NumberSequence.new(0.25, 1)
	impact.Color = ColorSequence.new(Color3.fromRGB(205, 241, 255))
	impact.LightEmission = 0.6
	impact.Parent = endpointAttachment
	impactEmitter = impact
end

local function updateWaterStream(position: Vector3, hasImpact: boolean)
	if waterEndpoint then
		waterEndpoint.Position = position
	end
	if waterBeam then
		waterBeam.Enabled = isSpraying
		local nozzlePosition = waterBeam.Attachment0 and waterBeam.Attachment0.WorldPosition
		local distance = if nozzlePosition then (position - nozzlePosition).Magnitude else 0
		waterBeam.Width0 = 0.1
		waterBeam.Width1 = math.clamp(0.16 + distance * 0.022, 0.22, 2.5)
	end
	if impactEmitter then
		impactEmitter.Enabled = isSpraying and hasImpact
	end
end

local function ensureSprayEmitter(tool: Tool): ParticleEmitter?
	local nozzle = getNozzle(tool)
	if nozzle == nil then
		return nil
	end

	local existing = nozzle:FindFirstChild("SprayParticles")
	if existing ~= nil and existing:IsA("ParticleEmitter") then
		return existing
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SprayParticles"
	emitter.Enabled = false
	-- This is only a small nozzle mist. The Beam is the actual water stream;
	-- high-speed particles would travel along the Handle's fixed orientation.
	emitter.Rate = 45
	emitter.Lifetime = NumberRange.new(0.04, 0.08)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.SpreadAngle = Vector2.new(18, 18)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Size = NumberSequence.new(0.1)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	emitter.LightEmission = 0.35
	emitter.Parent = nozzle

	return emitter
end

local function getCursorRay(): Ray?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	-- PlayerMouse.UnitRay is generated from the actual mouse hotspot by Roblox,
	-- avoiding manual top-bar/safe-inset conversions that vary by device.
	if UserInputService.MouseEnabled then
		return PLAYER_MOUSE.UnitRay
	end

	local viewportCenter = camera.ViewportSize * 0.5
	return camera:ViewportPointToRay(viewportCenter.X, viewportCenter.Y)
end

local function gatherDirtPixels(
	pixelFolder: Instance,
	centerRow: number,
	centerColumn: number,
	brushRadius: number
): {Instance}
	local pixels: {Instance} = {}
	for rowOffset = -brushRadius, brushRadius do
		for columnOffset = -brushRadius, brushRadius do
			if rowOffset * rowOffset + columnOffset * columnOffset > brushRadius * brushRadius then
				continue
			end
			local pixel = pixelFolder:FindFirstChild(string.format(
				"Pixel_%d_%d",
				centerRow + rowOffset,
				centerColumn + columnOffset
			))
			if pixel and CollectionService:HasTag(pixel, DIRT_TAG) then
				table.insert(pixels, pixel)
			end
		end
	end
	return pixels
end

local function findBenchDirtFolder(instance: Instance): Instance?
	if instance:GetAttribute("DirtPatch") == true then
		return instance.Parent
	end

	local ancestor: Instance? = instance
	while ancestor ~= nil and ancestor ~= Workspace do
		if ancestor:GetAttribute("CleanableJobModel") == true then
			return ancestor:FindFirstChild("DirtPixels")
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function gatherNearbyDirtPatches(folder: Instance, hitPosition: Vector3, worldRadius: number): {Instance}
	local patches: {Instance} = {}
	for _, candidate in folder:GetChildren() do
		if candidate:IsA("BasePart")
			and candidate:GetAttribute("DirtPatch") == true
			and CollectionService:HasTag(candidate, DIRT_TAG)
			and (candidate.Position - hitPosition).Magnitude <= worldRadius
		then
			table.insert(patches, candidate)
		end
	end
	return patches
end

local function findDirtSegments(
	hitInstance: Instance,
	hitPosition: Vector3,
	brushRadius: number,
	worldBrushRadius: number
): {Instance}
	if hitInstance:GetAttribute("DirtPatch") == true then
		local patchFolder = findBenchDirtFolder(hitInstance)
		if patchFolder ~= nil then
			return gatherNearbyDirtPatches(patchFolder, hitPosition, worldBrushRadius)
		end
	end

	if hitInstance:GetAttribute("BenchCleanableSurface") == true then
		local patchFolder = findBenchDirtFolder(hitInstance)
		if patchFolder ~= nil then
			return gatherNearbyDirtPatches(patchFolder, hitPosition, worldBrushRadius)
		end
	end

	if hitInstance:IsA("BasePart") and hitInstance:GetAttribute("DirtPixel") == true then
		local centerRow = hitInstance:GetAttribute("DirtRow")
		local centerColumn = hitInstance:GetAttribute("DirtColumn")
		local pixelFolder = hitInstance.Parent
		if typeof(centerRow) == "number" and typeof(centerColumn) == "number" and pixelFolder ~= nil then
			return gatherDirtPixels(pixelFolder, centerRow, centerColumn, brushRadius)
		end
	end

	-- Once a cleaned logical pixel becomes non-queryable, the ray hits the
	-- cleanable surface beneath it. Resolve that world hit back into the same
	-- validation grid so nearby visual cleaning is still measured accurately.
	if hitInstance:IsA("BasePart") and hitInstance:GetAttribute("CleanableSurface") == true then
		local columns = hitInstance:GetAttribute("DirtColumns")
		local rows = hitInstance:GetAttribute("DirtRows")
		local pixelFolder = hitInstance.Parent and hitInstance.Parent:FindFirstChild("DirtPixels")
		if typeof(columns) == "number" and typeof(rows) == "number" and pixelFolder ~= nil then
			local localPosition = hitInstance.CFrame:PointToObjectSpace(hitPosition)
			local u = math.clamp(localPosition.X / hitInstance.Size.X + 0.5, 0, 0.99999)
			local v = math.clamp(localPosition.Z / hitInstance.Size.Z + 0.5, 0, 0.99999)
			local centerColumn = math.floor(u * columns) + 1
			local centerRow = math.floor(v * rows) + 1
			return gatherDirtPixels(pixelFolder, centerRow, centerColumn, brushRadius)
		end
	end

	if CollectionService:HasTag(hitInstance, DIRT_TAG) then
		return { hitInstance }
	end

	-- Decals do not receive raycast hits themselves. Supporting a tagged Decal
	-- under the hit part keeps the artist workflow flexible.
	for _, child in hitInstance:GetChildren() do
		if child:IsA("Decal") and CollectionService:HasTag(child, DIRT_TAG) then
			return { child }
		end
	end

	return {}
end

local function finishSegment(segment: Instance)
	if not CollectionService:HasTag(segment, DIRT_TAG) then
		return
	end

	CollectionService:RemoveTag(segment, DIRT_TAG)
	if segment:IsA("BasePart") then
		segment.CanQuery = false
	elseif segment:IsA("Frame") then
		segment.Visible = false
	end
	if not pendingCleanLookup[segment] then
		pendingCleanLookup[segment] = true
		table.insert(pendingCleanSegments, segment)
	end

	local progressSignal = playerGui:FindFirstChild("JobProgressPredicted")
	if progressSignal ~= nil and progressSignal:IsA("BindableEvent") then
		progressSignal:Fire(segment)
	end
end

local function cleanSegment(segment: Instance, _deltaTime: number, pressureMultiplier: number)
	if activeCleanTweens[segment] then
		return
	end

	local currentProgress = segmentProgress[segment]
	if currentProgress == nil then
		if segment:IsA("Frame") or segment:IsA("BasePart") then
			currentProgress = 0
		elseif segment:IsA("Decal") then
			currentProgress = segment.Transparency
		else
			return
		end
	end
	local isDirtPixel = segment:GetAttribute("DirtPixel") == true
	local powerMultiplier = if segment:IsA("Frame") or isDirtPixel then PIXEL_CLEAN_POWER else 1
	local targetProgress = math.min(
		1,
		currentProgress + getCleanSpeed() * CLEAN_TWEEN_STEP * powerMultiplier * pressureMultiplier
	)
	local goals: {[string]: any} = {}

	if segment:IsA("BasePart") then
		local originalTransparency = originalPartTransparency[segment]
		if originalTransparency == nil then
			originalTransparency = segment.Transparency
			originalPartTransparency[segment] = originalTransparency
		end
		goals.Transparency = originalTransparency + (1 - originalTransparency) * targetProgress
	elseif segment:IsA("Decal") then
		goals.Transparency = targetProgress
	elseif segment:IsA("Frame") then
		local originalTransparency = originalGuiTransparency[segment]
		if originalTransparency == nil then
			originalTransparency = segment.BackgroundTransparency
			originalGuiTransparency[segment] = originalTransparency
		end
		goals.BackgroundTransparency = originalTransparency + (1 - originalTransparency) * targetProgress
	else
		return
	end

	activeCleanTweens[segment] = true
	local tween = TweenService:Create(segment, TweenInfo.new(CLEAN_TWEEN_STEP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	tween.Completed:Once(function()
		activeCleanTweens[segment] = nil
		segmentProgress[segment] = targetProgress
		if targetProgress >= 1 then
			finishSegment(segment)
		end
	end)
	tween:Play()
end

local function connectTool(tool: Tool)
	local isKnownWasher = tool:GetAttribute("IsPressureWasher") == true or Washers:FindFirstChild(tool.Name) ~= nil
	if connectedTools[tool] or not isKnownWasher then
		return
	end
	connectedTools[tool] = true

	tool.Equipped:Connect(function()
		activeTool = tool
		sprayEmitter = ensureSprayEmitter(tool)
		ensureWaterStream(tool)
	end)

	tool.Unequipped:Connect(function()
		if activeTool == tool then
			setSprayEnabled(false)
			clearWaterStream()
			activeTool = nil
			sprayEmitter = nil
		end
	end)

	-- Tool activation supports mouse, touch, and gamepad triggers.
	tool.Activated:Connect(function()
		if activeTool == tool then
			setSprayEnabled(true)
		end
	end)

	tool.Deactivated:Connect(function()
		if activeTool == tool then
			setSprayEnabled(false)
		end
	end)
end

local function watchContainer(container: Instance): RBXScriptConnection
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			connectTool(child)
		end
	end

	return container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			connectTool(child)
		end
	end)
end

watchContainer(PLAYER:WaitForChild("Backpack"))
local characterConnection: RBXScriptConnection? = nil
PLAYER.CharacterAdded:Connect(function(character)
	if characterConnection then
		characterConnection:Disconnect()
	end
	characterConnection = watchContainer(character)
end)
if PLAYER.Character ~= nil then
	characterConnection = watchContainer(PLAYER.Character)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 and activeTool ~= nil then
		setSprayEnabled(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		setSprayEnabled(false)
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	cleanReportAccumulator += deltaTime
	if cleanReportAccumulator >= CLEAN_REPORT_INTERVAL then
		cleanReportAccumulator %= CLEAN_REPORT_INTERVAL
		flushCleanReports()
	end

	if not isSpraying or activeTool == nil then
		waterReportAccumulator = 0
		return
	end

	local ownsInfiniteWater = PLAYER:GetAttribute("OwnsInfiniteWater") == true
	local authoritativeWater = PLAYER:GetAttribute("Water")
	if not ownsInfiniteWater and typeof(authoritativeWater) == "number" and authoritativeWater <= 0 then
		setSprayEnabled(false)
		return
	end

	waterReportAccumulator += deltaTime
	local shouldReportWater = waterReportAccumulator >= WATER_REPORT_INTERVAL
	if shouldReportWater then
		waterReportAccumulator -= WATER_REPORT_INTERVAL
	end

	local nozzle = getNozzle(activeTool)
	local character = PLAYER.Character
	if nozzle == nil or character == nil then
		if shouldReportWater then
			SprayWaterRequest:FireServer()
		end
		setSprayEnabled(false)
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, activeTool }
	raycastParams.IgnoreWater = true

	-- Aim through the actual cursor from the camera first. mouse.Hit can fall
	-- back to an unrelated world CFrame when it has no reliable target.
	local cursorRay = getCursorRay()
	if cursorRay == nil or cursorRay.Direction.Magnitude < 0.001 then
		if shouldReportWater then
			SprayWaterRequest:FireServer()
		end
		return
	end
	local cursorResult = Workspace:Raycast(
		cursorRay.Origin,
		cursorRay.Direction.Unit * MAX_SPRAY_DISTANCE,
		raycastParams
	)
	local target = if cursorResult
		then cursorResult.Position
		else cursorRay.Origin + cursorRay.Direction.Unit * MAX_SPRAY_DISTANCE
	local origin = nozzle.Position
	local offset = target - origin
	local pressureMultiplier = getPressureMultiplier(offset.Magnitude)
	local brushScale = 1 + (1 - pressureMultiplier) * 1.25
	local logicalBrushRadius = math.max(PIXEL_BRUSH_RADIUS, math.round(PIXEL_BRUSH_RADIUS * brushScale))
	local worldBrushRadius = BASE_WORLD_BRUSH_RADIUS * brushScale
	local segments = if cursorResult
		then findDirtSegments(cursorResult.Instance, cursorResult.Position, logicalBrushRadius, worldBrushRadius)
		else {}
	local representativeSegment = segments[1]
	if cursorResult ~= nil then
		local hitJobID = cursorResult.Instance:GetAttribute("JobID")
		local isActiveJobTarget = activeJobID ~= nil and hitJobID == activeJobID
		local hitDriveway = cursorResult.Instance == dirtDriveway
			or cursorResult.Instance:GetAttribute("DirtPixel") == true
		if isActiveJobTarget and hitDriveway then
			cleanHighResolutionDirt(cursorResult.Position, pressureMultiplier, brushScale)
		else
			previousDirtImagePoint = nil
		end
	else
		previousDirtImagePoint = nil
	end
	if shouldReportWater then
		SprayWaterRequest:FireServer(representativeSegment)
	end

	-- The endpoint uses the exact same camera hit that selects dirt. Using a
	-- second ray from the nozzle used to strike a neighboring pixel at shallow
	-- angles, making the water line appear offset from the mouse cursor.
	if offset.Magnitude < 0.01 then
		updateWaterStream(origin, false)
		return
	end
	updateWaterStream(target, cursorResult ~= nil)

	-- Cleaning is selected from the camera-to-cursor ray and is only permitted
	-- for dirt belonging to the player's currently confirmed active job.
	if cursorResult ~= nil and cursorResult.Instance:GetAttribute("DirtPixel") == true and not loggedDrivewayTarget then
		loggedDrivewayTarget = true
		print(string.format(
			"DIAGNOSTIC: Washer cursor hit an exact dirt region at %s and resolved %d nearby regions.",
			tostring(cursorResult.Position),
			#segments
		))
	end
	if representativeSegment ~= nil and representativeSegment:GetAttribute("JobID") == activeJobID then
		for _, segment in segments do
			cleanSegment(segment, deltaTime, pressureMultiplier)
		end
	end
end)
