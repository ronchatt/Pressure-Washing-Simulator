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
local DISTANCE_RESISTANCE_EXPONENT = 1.35
local HOUSE_JOB_ID = "SingleStoryHouse_1"
local DRIVEWAY_JOB_ID = "Driveway_1"
local CAR_JOB_ID = "Car_1"
local HOUSE_PIXELS_PER_STUD = 24
-- Large buildings contain far more validation regions than props. These
-- moderate boosts keep the starter washer brisk on house grime without
-- changing the difficulty of benches, fences, or future smaller jobs.
local HOUSE_BRUSH_RADIUS_MULTIPLIER = 2.35
local HOUSE_CLEAN_POWER_MULTIPLIER = 2.1
local HOUSE_VISUAL_FADE_MULTIPLIER = 3.1
local HOUSE_SPRAY_VISUAL_MULTIPLIER = 1.65
local CAR_BRUSH_RADIUS_MULTIPLIER = 1.55
local DRIVEWAY_BRUSH_RADIUS_MULTIPLIER = 2.5

type LiquidDirtCanvas = {
	Part: Part,
	Image: EditableImage,
	Pixels: buffer,
	Width: number,
	Height: number,
	Normal: Vector3,
	AxisU: Vector3,
	AxisV: Vector3,
	Plane: number,
	MinU: number,
	MaxU: number,
	MinV: number,
	MaxV: number,
}

type DrivewayDirtCanvas = {
	Part: Part,
	Source: BasePart,
	Image: EditableImage,
	Pixels: buffer,
	Width: number,
	Height: number,
}

type HouseSurfaceGroup = {
	Normal: Vector3,
	AxisU: Vector3,
	AxisV: Vector3,
	Plane: number,
	Patches: {BasePart},
	MinU: number,
	MaxU: number,
	MinV: number,
	MaxV: number,
}

type DirtSpatialIndex = {
	CellSize: number,
	Cells: {[string]: {BasePart}},
}

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
local waterSplashEmitter: ParticleEmitter? = nil
local mudRunoffEmitter: ParticleEmitter? = nil
local houseSprayVisualActive = false
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
local activeIncludedJobIDs: {string} = {}
local activeIncludedLookup: {[string]: boolean} = {}
local currentSprayJobID: string? = nil
local pendingCleanSegments: {Instance} = {}
local pendingCleanLookup: {[Instance]: boolean} = {}
local cleanReportAccumulator = 0
local houseDirtCanvases: {LiquidDirtCanvas} = {}
local rebuildHouseLiquidDirt: (() -> ())? = nil
local drivewayDirtCanvas: DrivewayDirtCanvas? = nil
local rebuildDrivewayLiquidDirt: (() -> ())? = nil
local drivewayDirtSpatialCache = setmetatable({} :: {[Instance]: DirtSpatialIndex}, { __mode = "k" })

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
			elseif descendant:IsA("BasePart") and descendant:GetAttribute("DirtVisualLobe") == true then
				local originalTransparency = descendant:GetAttribute("OriginalTransparency")
				if typeof(originalTransparency) == "number" then
					descendant.Transparency = originalTransparency
				end
				descendant.CanQuery = true
			elseif descendant:IsA("Decal") and descendant:GetAttribute("DirtVisual") == true then
				local originalTransparency = descendant:GetAttribute("OriginalTransparency")
				if typeof(originalTransparency) == "number" then
					descendant.Transparency = originalTransparency
				end
			end
		end
	end

	if jobID == "Bench_1" and dirtImage ~= nil and dirtPixelBuffer ~= nil then
		fillDirtBuffer(dirtPixelBuffer)
		dirtImage:WritePixelsBuffer(Vector2.zero, DIRT_IMAGE_SIZE, dirtPixelBuffer)
	end
	if jobID == HOUSE_JOB_ID and rebuildHouseLiquidDirt ~= nil then
		rebuildHouseLiquidDirt()
	end
	if jobID == DRIVEWAY_JOB_ID and rebuildDrivewayLiquidDirt ~= nil then
		rebuildDrivewayLiquidDirt()
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
		activeIncludedJobIDs = {}
		activeIncludedLookup = {}
		if typeof(state.IncludedJobIDs) == "table" then
			for _, jobID in state.IncludedJobIDs do
				if typeof(jobID) == "string" then
					table.insert(activeIncludedJobIDs, jobID)
					activeIncludedLookup[jobID] = true
					resetJobDirt(jobID)
				end
			end
		else
			table.insert(activeIncludedJobIDs, state.JobID)
			activeIncludedLookup[state.JobID] = true
			resetJobDirt(state.JobID)
		end
	elseif state.State == "Quit" then
		pendingCleanSegments = {}
		pendingCleanLookup = {}
		activeJobID = nil
		for _, jobID in activeIncludedJobIDs do resetJobDirt(jobID) end
		activeIncludedJobIDs = {}
		activeIncludedLookup = {}
	elseif state.State == "Completed" then
		local completedHouse = activeIncludedLookup[HOUSE_JOB_ID] == true
		local completedDriveway = activeIncludedLookup[DRIVEWAY_JOB_ID] == true
		pendingCleanSegments = {}
		pendingCleanLookup = {}
		activeJobID = nil
		activeIncludedJobIDs = {}
		activeIncludedLookup = {}
		previousDirtImagePoint = nil
		if completedHouse then
			for _, canvas in houseDirtCanvases do
				canvas.Part:Destroy()
				canvas.Image:Destroy()
			end
			houseDirtCanvases = {}
		end
		if completedDriveway and drivewayDirtCanvas ~= nil then
			drivewayDirtCanvas.Part:Destroy()
			drivewayDirtCanvas.Image:Destroy()
			drivewayDirtCanvas = nil
		end
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

local function destroyHouseLiquidDirt()
	for _, canvas in houseDirtCanvases do
		canvas.Part:Destroy()
		canvas.Image:Destroy()
	end
	houseDirtCanvases = {}
end

local function getStableSurfaceBasis(normal: Vector3): (Vector3, Vector3)
	local reference = if math.abs(normal.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
	local axisU = (reference - normal * reference:Dot(normal)).Unit
	return axisU, normal:Cross(axisU).Unit
end

local function paintLiquidBlob(
	pixels: buffer,
	width: number,
	height: number,
	centerX: number,
	centerY: number,
	radiusX: number,
	radiusY: number,
	seed: number
)
	local minX = math.max(0, math.floor(centerX - radiusX * 1.2))
	local maxX = math.min(width - 1, math.ceil(centerX + radiusX * 1.2))
	local minY = math.max(0, math.floor(centerY - radiusY * 1.2))
	local maxY = math.min(height - 1, math.ceil(centerY + radiusY * 1.2))

	for y = minY, maxY do
		for x = minX, maxX do
			local dx = (x - centerX) / math.max(radiusX, 1)
			local dy = (y - centerY) / math.max(radiusY, 1)
			local distance = math.sqrt(dx * dx + dy * dy)
			local angle = math.atan2(dy, dx)
			local edgeWarp = math.noise(x * 0.075 + seed, y * 0.075 - seed, seed * 0.17) * 0.5
				+ math.sin(angle * 3 + seed) * 0.1
			if distance <= 0.86 + edgeWarp then
				local index = (y * width + x) * 4
				local centerStrength = math.clamp(1 - distance, 0, 1)
				local alpha = math.floor(150 + centerStrength * 92)
				local currentAlpha = buffer.readu8(pixels, index + 3)
				if alpha > currentAlpha then
					local stainNoise = math.noise(x * 0.035, y * 0.035, seed * 0.29)
					local red: number
					local green: number
					local blue: number
					if stainNoise > 0.38 then
						-- Sickly organic grime mixed into the mud.
						red, green, blue = 32, 39, 17
					elseif stainNoise < -0.42 then
						-- Rust and old brown runoff pockets.
						red, green, blue = 67, 35, 15
					else
						-- Predominantly wet, nearly black mud.
						local variation = math.floor(math.noise(x * 0.11, y * 0.11, seed) * 9)
						red, green, blue = 29 + variation, 23 + math.floor(variation * 0.45), 16
					end
					buffer.writeu8(pixels, index, math.clamp(red, 0, 255))
					buffer.writeu8(pixels, index + 1, math.clamp(green, 0, 255))
					buffer.writeu8(pixels, index + 2, math.clamp(blue, 0, 255))
					buffer.writeu8(pixels, index + 3, alpha)
				end
			end
		end
	end
end

local function buildHouseLiquidDirt()
	destroyHouseLiquidDirt()
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
	local site = jobSites and jobSites:FindFirstChild(HOUSE_JOB_ID)
	local dirtFolder = site and site:FindFirstChild("DirtPixels")
	if site == nil or dirtFolder == nil or site:GetAttribute("UsesLiquidDirtCanvas") ~= true then
		return
	end

	local groups: {[string]: HouseSurfaceGroup} = {}
	for _, descendant in dirtFolder:GetChildren() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("DirtPixel") == true then
			local normal = descendant.CFrame.RightVector.Unit
			local plane = normal:Dot(descendant.Position)
			local key = string.format(
				"%d:%d:%d:%d",
				math.round(normal.X * 8),
				math.round(normal.Y * 8),
				math.round(normal.Z * 8),
				math.round(plane * 2)
			)
			local group = groups[key]
			if group == nil then
				local axisU, axisV = getStableSurfaceBasis(normal)
				group = {
					Normal = normal,
					AxisU = axisU,
					AxisV = axisV,
					Plane = plane,
					Patches = {},
					MinU = math.huge,
					MaxU = -math.huge,
					MinV = math.huge,
					MaxV = -math.huge,
				}
				groups[key] = group
			end
			table.insert(group.Patches, descendant)
			local u = group.AxisU:Dot(descendant.Position)
			local v = group.AxisV:Dot(descendant.Position)
			group.MinU = math.min(group.MinU, u)
			group.MaxU = math.max(group.MaxU, u)
			group.MinV = math.min(group.MinV, v)
			group.MaxV = math.max(group.MaxV, v)
		end
	end

	local canvasIndex = 0
	for _, group in groups do
		canvasIndex += 1
		local margin = 0.48
		group.MinU -= margin
		group.MaxU += margin
		group.MinV -= margin
		group.MaxV += margin
		local spanU = math.max(0.25, group.MaxU - group.MinU)
		local spanV = math.max(0.25, group.MaxV - group.MinV)
		local width = math.clamp(math.ceil(spanV * HOUSE_PIXELS_PER_STUD), 48, 512)
		local height = math.clamp(math.ceil(spanU * HOUSE_PIXELS_PER_STUD), 48, 512)
		local success, editableResult = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(width, height) })
		end)
		if not success or editableResult == nil then
			warn("House liquid dirt canvas could not create an EditableImage.", editableResult)
			continue
		end

		local editable = editableResult :: EditableImage
		local pixels = buffer.create(width * height * 4)
		local paintedPoints: {{ U: number, V: number }} = {}
		for patchIndex, patch in group.Patches do
			local u = group.AxisU:Dot(patch.Position)
			local v = group.AxisV:Dot(patch.Position)
			local pixelX = (group.MaxV - v) / spanV * (width - 1)
			local pixelY = (group.MaxU - u) / spanU * (height - 1)
			local worldRadius = math.clamp(math.max(patch.Size.Y, patch.Size.Z) * 0.95, 0.46, 0.88)
			local radiusX = worldRadius / spanV * width * (0.76 + math.noise(patchIndex, 3, 9) * 0.72)
			local radiusY = worldRadius / spanU * height * (0.82 + math.noise(7, patchIndex, 5) * 0.92)
			paintLiquidBlob(pixels, width, height, pixelX, pixelY, radiusX, radiusY, patchIndex * 0.73)

			-- Vertical surfaces occasionally grow narrow gravity-driven drips.
			-- They taper and wander instead of forming straight geometric lines.
			if math.abs(group.Normal.Y) < 0.3 and math.noise(patchIndex * 0.57, group.Plane, 21) > 0.06 then
				local dripWorldLength = 0.45 + math.abs(math.noise(patchIndex, 14, 6)) * 1.7
				local dripPixels = dripWorldLength / spanU * height
				local dripSteps = math.max(3, math.ceil(dripPixels / math.max(radiusY * 0.55, 2)))
				for dripIndex = 1, dripSteps do
					local alpha = dripIndex / dripSteps
					local dripX = pixelX
						+ math.sin(alpha * math.pi * 1.4) * radiusX * 0.28
						+ math.noise(patchIndex, dripIndex, 33) * radiusX * 0.22
					local dripY = pixelY + dripPixels * alpha
					local taper = 1 - alpha * 0.62
					paintLiquidBlob(
						pixels,
						width,
						height,
						dripX,
						dripY,
						math.max(1.5, radiusX * 0.38 * taper),
						math.max(2, radiusY * 0.5 * taper),
						patchIndex * 1.13 + alpha
					)
				end
			end

			-- Join each dirty sample to its nearest existing neighbor on this
			-- surface. The geometry scan order is not spatially reliable, so using
			-- the previous sample produced isolated dots. These wandering, tapered
			-- bridges turn nearby samples into continuous muddy puddles and runoff.
			local nearestPoint: { U: number, V: number }? = nil
			local nearestDistance = math.huge
			for _, point in paintedPoints do
				local deltaU = u - point.U
				local deltaV = v - point.V
				local distance = math.sqrt(deltaU * deltaU + deltaV * deltaV)
				if distance < nearestDistance then
					nearestPoint = point
					nearestDistance = distance
				end
			end

			if nearestPoint ~= nil and nearestDistance > 0.05 and nearestDistance < 1.65 then
				local deltaU = u - nearestPoint.U
				local deltaV = v - nearestPoint.V
				local steps = math.max(2, math.ceil(nearestDistance / 0.16))
				local bend = math.noise(patchIndex * 0.41, group.Plane * 0.17, 12) * 0.24
				for stepIndex = 1, steps - 1 do
					local alpha = stepIndex / steps
					local curve = math.sin(alpha * math.pi) * bend
						+ math.sin(alpha * math.pi * 2) * bend * 0.22
					local pathU = nearestPoint.U + deltaU * alpha - deltaV / nearestDistance * curve
					local pathV = nearestPoint.V + deltaV * alpha + deltaU / nearestDistance * curve
					local pathX = (group.MaxV - pathV) / spanV * (width - 1)
					local pathY = (group.MaxU - pathU) / spanU * (height - 1)
					local middleWeight = 0.68 + math.sin(alpha * math.pi) * 0.18
					local widthWobble = 1 + math.noise(patchIndex, stepIndex * 0.51, 44) * 0.24
					paintLiquidBlob(
						pixels,
						width,
						height,
						pathX,
						pathY,
						radiusX * middleWeight * widthWobble,
						radiusY * middleWeight,
						patchIndex * 0.73 + alpha
					)
				end
			end
			table.insert(paintedPoints, { U = u, V = v })
		end
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)

		local centerU = (group.MinU + group.MaxU) * 0.5
		local centerV = (group.MinV + group.MaxV) * 0.5
		local center = group.Normal * group.Plane + group.AxisU * centerU + group.AxisV * centerV
		local canvasPart = Instance.new("Part")
		canvasPart.Name = string.format("LocalHouseDirtCanvas_%02d", canvasIndex)
		canvasPart.Size = Vector3.new(0.004, spanU, spanV)
		canvasPart.CFrame = CFrame.fromMatrix(
			center + group.Normal * 0.003,
			group.Normal,
			group.AxisU,
			group.AxisV
		)
		canvasPart.Anchored = true
		canvasPart.CanCollide = false
		canvasPart.CanTouch = false
		canvasPart.CanQuery = false
		canvasPart.CastShadow = false
		canvasPart.Transparency = 1
		canvasPart.Parent = site

		local surface = Instance.new("SurfaceGui")
		surface.Name = "LiquidMudSurface"
		surface.Face = Enum.NormalId.Right
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.CanvasSize = Vector2.new(width, height)
		surface.LightInfluence = 0.22
		surface.AlwaysOnTop = false
		surface.Parent = canvasPart

		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "LiquidMudImage"
		imageLabel.Size = UDim2.fromScale(1, 1)
		imageLabel.BackgroundTransparency = 1
		imageLabel.ImageContent = Content.fromObject(editable)
		imageLabel.Parent = surface

		table.insert(houseDirtCanvases, {
			Part = canvasPart,
			Image = editable,
			Pixels = pixels,
			Width = width,
			Height = height,
			Normal = group.Normal,
			AxisU = group.AxisU,
			AxisV = group.AxisV,
			Plane = group.Plane,
			MinU = group.MinU,
			MaxU = group.MaxU,
			MinV = group.MinV,
			MaxV = group.MaxV,
		})
	end
	print(string.format("DIAGNOSTIC: Created %d high-resolution house dirt canvases.", #houseDirtCanvases))
end

rebuildHouseLiquidDirt = buildHouseLiquidDirt

local function cleanHouseLiquidDirt(
	worldPosition: Vector3,
	surfaceNormal: Vector3,
	pressureMultiplier: number,
	brushScale: number,
	deltaTime: number
)
	for _, canvas in houseDirtCanvases do
		if canvas.Normal:Dot(surfaceNormal) < 0.62 then
			continue
		end
		if math.abs(canvas.Normal:Dot(worldPosition) - canvas.Plane) > 0.38 then
			continue
		end
		local u = canvas.AxisU:Dot(worldPosition)
		local v = canvas.AxisV:Dot(worldPosition)
		if u < canvas.MinU or u > canvas.MaxU or v < canvas.MinV or v > canvas.MaxV then
			continue
		end

		local spanU = canvas.MaxU - canvas.MinU
		local spanV = canvas.MaxV - canvas.MinV
		local pixelX = (canvas.MaxV - v) / spanV * (canvas.Width - 1)
		local pixelY = (canvas.MaxU - u) / spanU * (canvas.Height - 1)
		local configuredWidth = PLAYER:GetAttribute("WasherSprayWidth")
		local washerWidth = if typeof(configuredWidth) == "number" then math.max(configuredWidth, 0.1) else 1
		local worldRadius = BASE_WORLD_BRUSH_RADIUS * brushScale * HOUSE_BRUSH_RADIUS_MULTIPLIER * washerWidth
		local radiusX = math.max(2, worldRadius / spanV * canvas.Width)
		local radiusY = math.max(2, worldRadius / spanU * canvas.Height)
		local minX = math.max(0, math.floor(pixelX - radiusX))
		local maxX = math.min(canvas.Width - 1, math.ceil(pixelX + radiusX))
		local minY = math.max(0, math.floor(pixelY - radiusY))
		local maxY = math.min(canvas.Height - 1, math.ceil(pixelY + radiusY))
		local regionWidth = maxX - minX + 1
		local regionHeight = maxY - minY + 1
		local region = buffer.create(regionWidth * regionHeight * 4)

		for y = minY, maxY do
			for x = minX, maxX do
				local dx = (x - pixelX) / radiusX
				local dy = (y - pixelY) / radiusY
				local distance = math.sqrt(dx * dx + dy * dy)
				local fullIndex = (y * canvas.Width + x) * 4
				if distance <= 1 then
					local strength = (1 - distance) ^ 0.65
					local alpha = buffer.readu8(canvas.Pixels, fullIndex + 3)
					local fade = math.max(1, math.floor(
						(145 + 430 * strength)
							* pressureMultiplier
							* HOUSE_VISUAL_FADE_MULTIPLIER
							* deltaTime
					))
					buffer.writeu8(canvas.Pixels, fullIndex + 3, math.max(0, alpha - fade))
				end
				local regionIndex = ((y - minY) * regionWidth + (x - minX)) * 4
				buffer.writeu8(region, regionIndex, buffer.readu8(canvas.Pixels, fullIndex))
				buffer.writeu8(region, regionIndex + 1, buffer.readu8(canvas.Pixels, fullIndex + 1))
				buffer.writeu8(region, regionIndex + 2, buffer.readu8(canvas.Pixels, fullIndex + 2))
				buffer.writeu8(region, regionIndex + 3, buffer.readu8(canvas.Pixels, fullIndex + 3))
			end
		end
		canvas.Image:WritePixelsBuffer(Vector2.new(minX, minY), Vector2.new(regionWidth, regionHeight), region)
	end
end

local function destroyDrivewayLiquidDirt()
	if drivewayDirtCanvas == nil then
		return
	end
	drivewayDirtCanvas.Part:Destroy()
	drivewayDirtCanvas.Image:Destroy()
	drivewayDirtCanvas = nil
end

local function fillDrivewayDirtBuffer(source: BasePart, pixels: buffer, width: number, height: number)
	for y = 0, height - 1 do
		local v = y / math.max(height - 1, 1)
		for x = 0, width - 1 do
			local u = x / math.max(width - 1, 1)
			local localX = (u - 0.5) * source.Size.X
			local localZ = (v - 0.5) * source.Size.Z
			local worldPoint = source.CFrame:PointToWorldSpace(Vector3.new(localX, source.Size.Y * 0.5, localZ))
			local macro = math.noise(worldPoint.X * 0.032, worldPoint.Z * 0.032, 4.7)
			local middle = math.noise(worldPoint.X * 0.095 + 19, worldPoint.Z * 0.095 - 31, 9.2)
			local fine = math.noise(worldPoint.X * 0.31 - 11, worldPoint.Z * 0.31 + 23, 15.6)
			local moss = math.clamp(
				(math.noise(worldPoint.X * 0.054, worldPoint.Z * 0.054, 28.4) + 0.08) * 1.55,
				0,
				1
			)
			local rust = math.clamp(
				(math.noise(worldPoint.X * 0.071 + 43, worldPoint.Z * 0.071, 37.1) + 0.03) * 1.7,
				0,
				1
			)
			local ochre = math.clamp(
				(math.noise(worldPoint.X * 0.12 - 51, worldPoint.Z * 0.12 + 8, 45.6) - 0.06) * 1.8,
				0,
				1
			)
			local oily = math.clamp(
				(math.noise(worldPoint.X * 0.043 + 7, worldPoint.Z * 0.043 - 17, 52.9) - 0.13) * 1.8,
				0,
				1
			)
			local grain = math.noise(worldPoint.X * 0.92 + 61, worldPoint.Z * 0.92 - 47, 63.2)
			local grit = math.max(0, grain - 0.06)
			local pitting = math.abs(math.noise(worldPoint.X * 0.47 - 33, worldPoint.Z * 0.47 + 72, 71.8))
			local stubborn = math.noise(worldPoint.X * 0.085, worldPoint.Z * 0.085, 34.7119) > 0.16

			-- Multi-scale noise creates broad muddy zones, branching discoloration,
			-- and fine grit without stamping a repeated texture across the surface.
			local red = 122 + macro * 22 + middle * 28 + fine * 16
				+ rust * 29 + ochre * 21 - moss * 13 - oily * 23 - grit * 62 - pitting * 12
			local green = 91 + macro * 17 + middle * 21 + fine * 14
				+ moss * 24 + ochre * 14 - rust * 10 - oily * 20 - grit * 54 - pitting * 10
			local blue = 56 + macro * 11 + middle * 15 + fine * 11
				+ moss * 7 + ochre * 2 - rust * 6 - oily * 16 - grit * 39 - pitting * 7
			local alpha = 127 + math.abs(macro) * 44 + math.max(0, middle) * 58
				+ math.abs(fine) * 29 + oily * 18 + grit * 83 + pitting * 21
			if stubborn then
				red *= 0.72
				green *= 0.72
				blue *= 0.68
				alpha += 42
			end

			local index = (y * width + x) * 4
			buffer.writeu8(pixels, index, math.clamp(math.floor(red), 42, 185))
			buffer.writeu8(pixels, index + 1, math.clamp(math.floor(green), 38, 155))
			buffer.writeu8(pixels, index + 2, math.clamp(math.floor(blue), 27, 112))
			buffer.writeu8(pixels, index + 3, math.clamp(math.floor(alpha), 88, 215))
		end
	end
end

local function buildDrivewayLiquidDirt()
	destroyDrivewayLiquidDirt()
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
	local site = jobSites and jobSites:FindFirstChild(DRIVEWAY_JOB_ID)
	local dirtFolder = site and site:FindFirstChild("DirtPixels")
	if site == nil or dirtFolder == nil or site:GetAttribute("UsesLiquidDirtCanvas") ~= true then
		return
	end

	local source = if site:IsA("Model") then site.PrimaryPart else nil
	if source == nil then
		for _, descendant in site:GetDescendants() do
			if descendant:IsA("BasePart") and descendant:GetAttribute("Cleanable3DSurface") == true
				and descendant:GetAttribute("DirtPixel") ~= true
			then
				source = descendant
				break
			end
		end
	end
	if source == nil then
		warn("Driveway liquid dirt could not find its concrete source part.")
		return
	end

	local width = math.clamp(math.ceil(source.Size.X * 14), 160, 512)
	local height = math.clamp(math.ceil(source.Size.Z * 9), 256, 768)
	local success, editableResult = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(width, height) })
	end)
	if not success or editableResult == nil then
		warn("Driveway liquid dirt canvas is unavailable.", editableResult)
		return
	end

	local editable = editableResult :: EditableImage
	local pixels = buffer.create(width * height * 4)
	fillDrivewayDirtBuffer(source, pixels, width, height)
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)

	local canvasPart = Instance.new("Part")
	canvasPart.Name = "LocalDrivewayDirtCanvas"
	canvasPart.Size = Vector3.new(source.Size.X, source.Size.Z, 0.02)
	canvasPart.CFrame = source.CFrame
		* CFrame.new(0, source.Size.Y * 0.5 + 0.012, 0)
		* CFrame.Angles(math.rad(-90), 0, 0)
	canvasPart.Anchored = true
	canvasPart.CanCollide = false
	canvasPart.CanTouch = false
	canvasPart.CanQuery = false
	canvasPart.CastShadow = false
	canvasPart.Transparency = 1
	canvasPart.Parent = site

	local surface = Instance.new("SurfaceGui")
	surface.Name = "LiquidDrivewayMudSurface"
	surface.Face = Enum.NormalId.Back
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(width, height)
	surface.LightInfluence = 0.3
	surface.AlwaysOnTop = false
	surface.Parent = canvasPart

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "LiquidDrivewayMudImage"
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.BackgroundTransparency = 1
	imageLabel.ImageContent = Content.fromObject(editable)
	imageLabel.Parent = surface

	drivewayDirtCanvas = {
		Part = canvasPart,
		Source = source,
		Image = editable,
		Pixels = pixels,
		Width = width,
		Height = height,
	}
	print(string.format("DIAGNOSTIC: Created a %dx%d non-repeating driveway dirt canvas.", width, height))
end

rebuildDrivewayLiquidDirt = buildDrivewayLiquidDirt

local function cleanDrivewayLiquidDirt(
	worldPosition: Vector3,
	pressureMultiplier: number,
	worldBrushRadius: number,
	deltaTime: number
)
	local canvas = drivewayDirtCanvas
	if canvas == nil then
		return
	end
	local localPosition = canvas.Source.CFrame:PointToObjectSpace(worldPosition)
	local u = math.clamp(localPosition.X / canvas.Source.Size.X + 0.5, 0, 1)
	local v = math.clamp(localPosition.Z / canvas.Source.Size.Z + 0.5, 0, 1)
	local pixelX = u * (canvas.Width - 1)
	local pixelY = v * (canvas.Height - 1)
	local radiusX = math.max(2, worldBrushRadius / canvas.Source.Size.X * canvas.Width)
	local radiusY = math.max(2, worldBrushRadius / canvas.Source.Size.Z * canvas.Height)
	local configuredCleanSpeed = PLAYER:GetAttribute("WasherCleanSpeed")
	local cleanSpeed = if typeof(configuredCleanSpeed) == "number" then configuredCleanSpeed else DEFAULT_CLEAN_SPEED
	local rawWasherPowerScale = math.clamp(cleanSpeed / DEFAULT_CLEAN_SPEED, 1, 4)
	local washerPowerScale = if rawWasherPowerScale <= 2.3
		then rawWasherPowerScale
		else 2.3 + (rawWasherPowerScale - 2.3) * 0.25
	local minX = math.max(0, math.floor(pixelX - radiusX))
	local maxX = math.min(canvas.Width - 1, math.ceil(pixelX + radiusX))
	local minY = math.max(0, math.floor(pixelY - radiusY))
	local maxY = math.min(canvas.Height - 1, math.ceil(pixelY + radiusY))
	local regionWidth = maxX - minX + 1
	local regionHeight = maxY - minY + 1
	local region = buffer.create(regionWidth * regionHeight * 4)

	for y = minY, maxY do
		for x = minX, maxX do
			local dx = (x - pixelX) / radiusX
			local dy = (y - pixelY) / radiusY
			local distance = math.sqrt(dx * dx + dy * dy)
			local fullIndex = (y * canvas.Width + x) * 4
			if distance <= 1 then
				local strength = (1 - distance) ^ 0.72
				local alpha = buffer.readu8(canvas.Pixels, fullIndex + 3)
				local fade = math.max(1, math.floor(
					(115 + 310 * strength) * pressureMultiplier * washerPowerScale * deltaTime
				))
				buffer.writeu8(canvas.Pixels, fullIndex + 3, math.max(0, alpha - fade))
			end
			local regionIndex = ((y - minY) * regionWidth + (x - minX)) * 4
			buffer.writeu8(region, regionIndex, buffer.readu8(canvas.Pixels, fullIndex))
			buffer.writeu8(region, regionIndex + 1, buffer.readu8(canvas.Pixels, fullIndex + 1))
			buffer.writeu8(region, regionIndex + 2, buffer.readu8(canvas.Pixels, fullIndex + 2))
			buffer.writeu8(region, regionIndex + 3, buffer.readu8(canvas.Pixels, fullIndex + 3))
		end
	end
	canvas.Image:WritePixelsBuffer(Vector2.new(minX, minY), Vector2.new(regionWidth, regionHeight), region)
end

task.spawn(initializeHighResolutionDirt)
task.spawn(function()
	local environment = Workspace:WaitForChild("EnvironmentFixtures", 15)
	local jobSites = environment and environment:WaitForChild("JobSites", 15)
	local site = if jobSites then jobSites:WaitForChild(HOUSE_JOB_ID, 15) else nil
	local dirtFolder = site and site:WaitForChild("DirtPixels", 15)
	if site and dirtFolder then
		local deadline = os.clock() + 15
		repeat
			local expectedCount = site:GetAttribute("DirtPatchCount")
			if typeof(expectedCount) == "number" and expectedCount > 0
				and #dirtFolder:GetChildren() >= expectedCount
			then
				break
			end
			task.wait(0.1)
		until os.clock() >= deadline
	end
	buildHouseLiquidDirt()
end)
task.spawn(function()
	local environment = Workspace:WaitForChild("EnvironmentFixtures", 15)
	local jobSites = environment and environment:WaitForChild("JobSites", 15)
	local site = if jobSites then jobSites:WaitForChild(DRIVEWAY_JOB_ID, 15) else nil
	local dirtFolder = site and site:WaitForChild("DirtPixels", 15)
	if site and dirtFolder then
		local deadline = os.clock() + 15
		repeat
			local expectedCount = site:GetAttribute("DirtPatchCount")
			if typeof(expectedCount) == "number" and expectedCount > 0
				and #dirtFolder:GetChildren() >= expectedCount
			then
				break
			end
			task.wait(0.1)
		until os.clock() >= deadline
	end
	buildDrivewayLiquidDirt()
end)

local function getCleanSpeed(): number
	local configuredSpeed = PLAYER:GetAttribute("WasherCleanSpeed")
	if typeof(configuredSpeed) == "number" then
		return configuredSpeed
	end

	return DEFAULT_CLEAN_SPEED
end

local function getWasherStat(attributeName: string, fallback: number): number
	local configuredValue = PLAYER:GetAttribute(attributeName)
	if typeof(configuredValue) == "number" then
		return math.max(configuredValue, 0.1)
	end
	return fallback
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
	if waterSplashEmitter ~= nil and not isSpraying then
		waterSplashEmitter.Enabled = false
	end
	if mudRunoffEmitter ~= nil and not isSpraying then
		mudRunoffEmitter.Enabled = false
		mudRunoffEmitter.Rate = 0
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
	local rangeMultiplier = getWasherStat("WasherEffectiveRange", 1)
	local fullPressureDistance = FULL_PRESSURE_DISTANCE * rangeMultiplier
	local pressureFalloffDistance = PRESSURE_FALLOFF_DISTANCE * rangeMultiplier
	if distance <= fullPressureDistance then
		return 1
	end
	local falloff = (distance - fullPressureDistance) / pressureFalloffDistance
	-- Pressure loses useful cleaning force faster than the stream loses visual
	-- reach. Close passes cut through mud; distant passes still work but meet
	-- noticeable resistance and require dwelling on the stain.
	local normalizedPressure = math.clamp(1 - falloff, 0, 1)
	return math.max(normalizedPressure ^ DISTANCE_RESISTANCE_EXPONENT, MIN_PRESSURE_MULTIPLIER)
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
	waterSplashEmitter = nil
	mudRunoffEmitter = nil
	houseSprayVisualActive = false
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
	beam.Width0 = 0.2
	beam.Width1 = 0.28
	beam.LightEmission = 0.08
	beam.Brightness = 0.25
	beam.Segments = 12
	beam.Texture = ""
	beam.Color = ColorSequence.new(Color3.fromRGB(235, 248, 250), Color3.fromRGB(176, 218, 226))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(0.55, 0.52),
		NumberSequenceKeypoint.new(1, 0.76),
	})
	beam.Parent = nozzle
	waterBeam = beam

	local impact = Instance.new("ParticleEmitter")
	impact.Name = "WaterImpactMist"
	impact.Enabled = false
	impact.Rate = 145
	impact.Lifetime = NumberRange.new(0.12, 0.28)
	impact.Speed = NumberRange.new(1.5, 4)
	impact.SpreadAngle = Vector2.new(80, 80)
	impact.Texture = "rbxasset://textures/particles/smoke_main.dds"
	impact.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(0.55, 0.4),
		NumberSequenceKeypoint.new(1, 0.58),
	})
	impact.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.52),
		NumberSequenceKeypoint.new(0.35, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	impact.Color = ColorSequence.new(Color3.fromRGB(205, 241, 255))
	impact.LightEmission = 0.15
	impact.Parent = endpointAttachment
	impactEmitter = impact

	local splash = Instance.new("ParticleEmitter")
	splash.Name = "WaterImpactDroplets"
	splash.Enabled = false
	splash.Rate = 285
	splash.Lifetime = NumberRange.new(0.14, 0.38)
	splash.Speed = NumberRange.new(5, 12)
	splash.Acceleration = Vector3.new(0, -32, 0)
	splash.Drag = 1.8
	splash.SpreadAngle = Vector2.new(100, 100)
	splash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	splash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.065),
		NumberSequenceKeypoint.new(0.65, 0.045),
		NumberSequenceKeypoint.new(1, 0.012),
	})
	splash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(0.7, 0.38),
		NumberSequenceKeypoint.new(1, 1),
	})
	splash.Color = ColorSequence.new(Color3.fromRGB(203, 235, 244), Color3.fromRGB(128, 198, 218))
	splash.LightEmission = 0.28
	splash.Orientation = Enum.ParticleOrientation.VelocityParallel
	splash.Parent = endpointAttachment
	waterSplashEmitter = splash

	-- Local-only muddy runoff: droplets inherit the impact point, fall under
	-- gravity, spread along the surface, and quickly fade. This suggests water
	-- mixing with grime without networking hundreds of physical liquid parts.
	local runoff = Instance.new("ParticleEmitter")
	runoff.Name = "MuddyRunoff"
	runoff.Enabled = false
	runoff.Rate = 0
	runoff.Lifetime = NumberRange.new(0.28, 0.62)
	runoff.Speed = NumberRange.new(1.2, 3.8)
	runoff.Acceleration = Vector3.new(0, -18, 0)
	runoff.Drag = 4
	runoff.SpreadAngle = Vector2.new(55, 55)
	runoff.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.14),
		NumberSequenceKeypoint.new(0.45, 0.09),
		NumberSequenceKeypoint.new(1, 0.025),
	})
	runoff.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.55, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	runoff.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(91, 67, 39)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(121, 96, 65)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(178, 198, 194)),
	})
	runoff.LightInfluence = 0.72
	runoff.Orientation = Enum.ParticleOrientation.VelocityParallel
	runoff.Rotation = NumberRange.new(-180, 180)
	runoff.RotSpeed = NumberRange.new(-90, 90)
	runoff.Parent = endpointAttachment
	mudRunoffEmitter = runoff
end

local function updateWaterStream(position: Vector3, hasImpact: boolean, mudIntensity: number)
	local useWideHouseSpray = currentSprayJobID == HOUSE_JOB_ID
	if useWideHouseSpray ~= houseSprayVisualActive then
		houseSprayVisualActive = useWideHouseSpray
		if sprayEmitter then
			sprayEmitter.SpreadAngle = if useWideHouseSpray then Vector2.new(7.8, 7.8) else Vector2.new(4.8, 4.8)
			sprayEmitter.Size = if useWideHouseSpray
				then NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.34),
					NumberSequenceKeypoint.new(0.55, 0.23),
					NumberSequenceKeypoint.new(1, 0.07),
				})
				else NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.27),
					NumberSequenceKeypoint.new(0.55, 0.18),
					NumberSequenceKeypoint.new(1, 0.055),
				})
		end
		if impactEmitter then
			impactEmitter.Rate = if useWideHouseSpray then 220 else 145
			impactEmitter.SpreadAngle = if useWideHouseSpray then Vector2.new(115, 115) else Vector2.new(80, 80)
			impactEmitter.Size = if useWideHouseSpray
				then NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.25),
					NumberSequenceKeypoint.new(0.55, 0.72),
					NumberSequenceKeypoint.new(1, 1.05),
				})
				else NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.16),
					NumberSequenceKeypoint.new(0.55, 0.4),
					NumberSequenceKeypoint.new(1, 0.58),
				})
		end
		if waterSplashEmitter then
			waterSplashEmitter.Rate = if useWideHouseSpray then 390 else 285
			waterSplashEmitter.SpreadAngle = if useWideHouseSpray then Vector2.new(125, 125) else Vector2.new(100, 100)
		end
	end
	if waterEndpoint then
		waterEndpoint.Position = position
	end
	if waterBeam then
		-- A soft scrolling texture supplies pressure and thickness while the
		-- separated droplets and impact emitters break up the silhouette. Low
		-- brightness and strong transparency keep it from reading as a laser.
		waterBeam.Enabled = isSpraying
		local nozzlePosition = waterBeam.Attachment0 and waterBeam.Attachment0.WorldPosition
		local distance = if nozzlePosition then (position - nozzlePosition).Magnitude else 0
		local washerWidth = getWasherStat("WasherSprayWidth", 1)
		local visualMultiplier = (if useWideHouseSpray then HOUSE_SPRAY_VISUAL_MULTIPLIER else 1) * washerWidth
		waterBeam.Width0 = 0.2 * math.sqrt(visualMultiplier)
		waterBeam.Width1 = math.clamp(0.24 + distance * 0.0022, 0.25, 0.38) * visualMultiplier

		-- Aim the droplet emitter through the exact cursor impact point. The
		-- particles carry the stream visually; the Beam is only a faint pressure
		-- core that prevents gaps on low-end devices.
		local originAttachment = waterBeam.Attachment0
		local nozzle = originAttachment and originAttachment.Parent
		if originAttachment and nozzle and nozzle:IsA("BasePart") and distance > 0.05 then
			originAttachment.CFrame = nozzle.CFrame:ToObjectSpace(CFrame.lookAt(originAttachment.WorldPosition, position))
		end
		if sprayEmitter then
			-- Base lifetime on the slow end of the velocity range so droplets do
			-- not disappear before reaching a distant cursor impact point.
			sprayEmitter.Lifetime = NumberRange.new(math.clamp(distance / 88 + 0.06, 0.08, 1.45))
			local baseRate = math.clamp(245 + distance * 0.8, 260, 335)
			sprayEmitter.Rate = baseRate * (if useWideHouseSpray then 1.28 else 1)
		end
	end
	if impactEmitter then
		impactEmitter.Enabled = isSpraying and hasImpact
	end
	if waterSplashEmitter then
		waterSplashEmitter.Enabled = isSpraying and hasImpact
	end
	if mudRunoffEmitter then
		local isWashingMud = isSpraying and mudIntensity > 0
		mudRunoffEmitter.Enabled = isWashingMud
		mudRunoffEmitter.Rate = if isWashingMud then 28 + 52 * mudIntensity else 0
	end
end

local function ensureSprayEmitter(tool: Tool): ParticleEmitter?
	local nozzle = getNozzle(tool)
	if nozzle == nil then
		return nil
	end

	local existing = nozzle:FindFirstChild("SprayParticles", true)
	if existing ~= nil and existing:IsA("ParticleEmitter") then
		existing:Destroy()
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

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SprayParticles"
	emitter.Enabled = false
	emitter.Rate = 285
	emitter.Lifetime = NumberRange.new(0.12)
	emitter.Speed = NumberRange.new(88, 108)
	emitter.Acceleration = Vector3.new(0, -8, 0)
	emitter.Drag = 0.65
	emitter.SpreadAngle = Vector2.new(4.8, 4.8)
	emitter.EmissionDirection = Enum.NormalId.Front
	-- Sparkle particles render as crisp individual droplets when stretched along
	-- their velocity. Mist remains reserved for the point of impact.
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.27),
		NumberSequenceKeypoint.new(0.55, 0.18),
		NumberSequenceKeypoint.new(1, 0.055),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.72, 0.34),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 244, 250), Color3.fromRGB(143, 207, 224))
	emitter.LightEmission = 0.42
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Parent = originAttachment

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
	if instance:GetAttribute("DirtVisualLobe") == true then
		local owner = instance.Parent
		if owner and owner:GetAttribute("DirtPatch") == true then
			return owner.Parent
		end
	end
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
	local site = folder.Parent
	if site ~= nil and site:GetAttribute("JobID") == DRIVEWAY_JOB_ID then
		local spatialIndex = drivewayDirtSpatialCache[folder]
		if spatialIndex == nil then
			local cellSize = 2.5
			spatialIndex = { CellSize = cellSize, Cells = {} }
			for _, candidate in folder:GetChildren() do
				if candidate:IsA("BasePart") and candidate:GetAttribute("DirtPatch") == true then
					local cellX = math.floor(candidate.Position.X / cellSize)
					local cellZ = math.floor(candidate.Position.Z / cellSize)
					local key = string.format("%d:%d", cellX, cellZ)
					local cell = spatialIndex.Cells[key]
					if cell == nil then
						cell = {}
						spatialIndex.Cells[key] = cell
					end
					table.insert(cell, candidate)
				end
			end
			drivewayDirtSpatialCache[folder] = spatialIndex
		end

		local cellRadius = math.ceil(worldRadius / spatialIndex.CellSize)
		local centerX = math.floor(hitPosition.X / spatialIndex.CellSize)
		local centerZ = math.floor(hitPosition.Z / spatialIndex.CellSize)
		for offsetX = -cellRadius, cellRadius do
			for offsetZ = -cellRadius, cellRadius do
				local cell = spatialIndex.Cells[string.format("%d:%d", centerX + offsetX, centerZ + offsetZ)]
				if cell ~= nil then
					for _, candidate in cell do
						if CollectionService:HasTag(candidate, DIRT_TAG)
							and (candidate.Position - hitPosition).Magnitude <= worldRadius
						then
							table.insert(patches, candidate)
						end
					end
				end
			end
		end
		return patches
	end

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
	if hitInstance:GetAttribute("DirtVisualLobe") == true then
		local owner = hitInstance.Parent
		local patchFolder = findBenchDirtFolder(hitInstance)
		if owner and owner:IsA("BasePart") and patchFolder ~= nil then
			return gatherNearbyDirtPatches(patchFolder, hitPosition, worldBrushRadius)
		end
	end
	if hitInstance:GetAttribute("DirtPatch") == true then
		local patchFolder = findBenchDirtFolder(hitInstance)
		if patchFolder ~= nil then
			return gatherNearbyDirtPatches(patchFolder, hitPosition, worldBrushRadius)
		end
	end

	if hitInstance:GetAttribute("BenchCleanableSurface") == true
		or hitInstance:GetAttribute("Cleanable3DSurface") == true
	then
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
		for _, child in segment:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("DirtVisualLobe") == true then
				child.CanQuery = false
			end
		end
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
	local configuredCleanPower = segment:GetAttribute("CleanPowerMultiplier")
	if typeof(configuredCleanPower) == "number" then
		powerMultiplier *= math.clamp(configuredCleanPower, 0.5, 4)
	end
	if segment:GetAttribute("JobID") == HOUSE_JOB_ID then
		powerMultiplier *= HOUSE_CLEAN_POWER_MULTIPLIER
	end
	local configuredResistance = segment:GetAttribute("DirtResistance")
	local dirtResistance = if typeof(configuredResistance) == "number"
		then math.clamp(configuredResistance, 0.5, 2.5)
		else 1
	local targetProgress = math.min(
		1,
		currentProgress + getCleanSpeed() * CLEAN_TWEEN_STEP * powerMultiplier * pressureMultiplier / dirtResistance
	)
	local dirtFolder = segment.Parent
	local jobSite = dirtFolder and dirtFolder.Parent
	local usesLiquidCanvas = isDirtPixel and jobSite ~= nil and jobSite:GetAttribute("UsesLiquidDirtCanvas") == true
	if usesLiquidCanvas then
		-- Liquid-canvas jobs render their fade in one EditableImage. Their
		-- transparent validation parts do not need hundreds of redundant Tweens.
		segmentProgress[segment] = targetProgress
		if targetProgress >= 1 then
			finishSegment(segment)
		end
		return
	end
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
	local configuredFadeDuration = segment:GetAttribute("FastFadeDuration")
	local fadeDuration = if typeof(configuredFadeDuration) == "number"
		then math.clamp(configuredFadeDuration, 0.03, 0.25)
		else CLEAN_TWEEN_STEP
	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(segment, tweenInfo, goals)
	if segment:IsA("BasePart") then
		for _, child in segment:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("DirtVisualLobe") == true then
				local lobeOriginal = originalPartTransparency[child]
				if lobeOriginal == nil then
					lobeOriginal = child.Transparency
					originalPartTransparency[child] = lobeOriginal
				end
				TweenService:Create(child, tweenInfo, {
					Transparency = lobeOriginal + (1 - lobeOriginal) * targetProgress,
				}):Play()
			elseif child:IsA("Decal") and child:GetAttribute("DirtVisual") == true then
				local originalTransparency = child:GetAttribute("OriginalTransparency")
				if typeof(originalTransparency) == "number" then
					TweenService:Create(child, tweenInfo, {
						Transparency = originalTransparency + (1 - originalTransparency) * targetProgress,
					}):Play()
				end
			end
		end
	end
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
		ensureWaterStream(tool)
		sprayEmitter = ensureSprayEmitter(tool)
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
		cursorRay.Direction.Unit * MAX_SPRAY_DISTANCE * getWasherStat("WasherEffectiveRange", 1),
		raycastParams
	)
	local target = if cursorResult
		then cursorResult.Position
		else cursorRay.Origin + cursorRay.Direction.Unit * MAX_SPRAY_DISTANCE * getWasherStat("WasherEffectiveRange", 1)
	local origin = nozzle.Position
	local offset = target - origin
	local pressureMultiplier = getPressureMultiplier(offset.Magnitude)
	local brushScale = 1 + (1 - pressureMultiplier) * 1.25
	local washerWidth = getWasherStat("WasherSprayWidth", 1)
	local logicalBrushRadius = math.max(PIXEL_BRUSH_RADIUS, math.round(PIXEL_BRUSH_RADIUS * brushScale * washerWidth))
	local hitJobID = if cursorResult then cursorResult.Instance:GetAttribute("JobID") else nil
	currentSprayJobID = if typeof(hitJobID) == "string" and activeIncludedLookup[hitJobID] then hitJobID else nil
	local rawDrivewayTierScale = math.clamp(getCleanSpeed() / DEFAULT_CLEAN_SPEED, 1, 4)
	local drivewayTierScale = if rawDrivewayTierScale <= 2.3
		then rawDrivewayTierScale
		else 2.3 + (rawDrivewayTierScale - 2.3) * 0.25
	local jobBrushMultiplier = if hitJobID == HOUSE_JOB_ID
		then HOUSE_BRUSH_RADIUS_MULTIPLIER
		elseif hitJobID == CAR_JOB_ID then CAR_BRUSH_RADIUS_MULTIPLIER
		elseif hitJobID == DRIVEWAY_JOB_ID
			then DRIVEWAY_BRUSH_RADIUS_MULTIPLIER * drivewayTierScale
		else 1
	local worldBrushRadius = BASE_WORLD_BRUSH_RADIUS * brushScale * jobBrushMultiplier * washerWidth
	local segments = if cursorResult
		then findDirtSegments(cursorResult.Instance, cursorResult.Position, logicalBrushRadius, worldBrushRadius)
		else {}
	local representativeSegment = segments[1]
	if cursorResult ~= nil then
		local isActiveJobTarget = typeof(hitJobID) == "string" and activeIncludedLookup[hitJobID] == true
		local hitDriveway = cursorResult.Instance == dirtDriveway
			or cursorResult.Instance:GetAttribute("DirtPixel") == true
		if isActiveJobTarget and hitDriveway then
			cleanHighResolutionDirt(cursorResult.Position, pressureMultiplier, brushScale)
		else
			previousDirtImagePoint = nil
		end
		if isActiveJobTarget and hitJobID == HOUSE_JOB_ID then
			cleanHouseLiquidDirt(
				cursorResult.Position,
				cursorResult.Normal,
				pressureMultiplier,
				brushScale,
				deltaTime
			)
		elseif isActiveJobTarget and hitJobID == DRIVEWAY_JOB_ID then
			cleanDrivewayLiquidDirt(
				cursorResult.Position,
				pressureMultiplier,
				worldBrushRadius,
				deltaTime
			)
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
		updateWaterStream(origin, false, 0)
		return
	end
	local mudIntensity = if representativeSegment ~= nil
		and activeIncludedLookup[representativeSegment:GetAttribute("JobID")] == true
		then pressureMultiplier
		else 0
	updateWaterStream(target, cursorResult ~= nil, mudIntensity)

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
	if representativeSegment ~= nil and activeIncludedLookup[representativeSegment:GetAttribute("JobID")] == true then
		for _, segment in segments do
			cleanSegment(segment, deltaTime, pressureMultiplier)
		end
	end
end)
