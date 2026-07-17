--!strict

print("DIAGNOSTIC: DevEnvironmentSetup script is RUNNING.")

-- Centralized development fixtures for testing jobs, the shop, and pets.
-- Vehicle models and parking-placeholder blocks are intentionally excluded.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local DevEnvironmentSetup = {}
local initialized = false

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function replaceChild(parent: Instance, name: string)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local function createGrassBaseplate(environment: Folder)
	local success, creationError = pcall(function()
		-- Rojo does not necessarily delete an unmanaged template Baseplate from
		-- the open Studio place. Remove copies to prevent surface z-fighting.
		for _, child in Workspace:GetChildren() do
			if child.Name == "Baseplate" and child ~= environment then
				child:Destroy()
			end
		end

		replaceChild(environment, "Baseplate")
		local baseplate = Instance.new("Part")
		baseplate.Name = "Baseplate"
		baseplate.Size = Vector3.new(2048, 20, 2048)
		baseplate.Position = Vector3.new(0, -10, 0)
		baseplate.Anchored = true
		baseplate.Color = Color3.fromRGB(99, 121, 57)
		baseplate.Material = Enum.Material.Grass
		baseplate.Locked = true
		baseplate.Parent = environment
	end)
	if success then
		print("DIAGNOSTIC: Created Baseplate successfully.")
	else
		warn("DIAGNOSTIC: Failed to create Baseplate", creationError)
	end
end

local function createInteractionFixtures(environment: Folder)
	local base = ensureFolder(environment, "Base")
	replaceChild(base, "Computer")
	replaceChild(base, "EggIncubator")
	replaceChild(base, "FireHydrant")

	local computerCreated, computerError = pcall(function()
		local computer = Instance.new("Part")
		computer.Name = "Computer"
		computer.Size = Vector3.new(4, 4, 2)
		computer.Position = Vector3.new(0, 5, 10)
		computer.Anchored = true
		computer.Color = Color3.fromRGB(48, 145, 210)
		computer.Material = Enum.Material.Metal
		computer.Parent = base
	end)
	if computerCreated then
		print("DIAGNOSTIC: Created Computer successfully.")
	else
		warn("DIAGNOSTIC: Failed to create Computer", computerError)
	end

	local incubatorCreated, incubatorError = pcall(function()
		local incubator = Instance.new("Part")
		incubator.Name = "EggIncubator"
		incubator.Shape = Enum.PartType.Ball
		incubator.Size = Vector3.new(4, 4, 4)
		incubator.Position = Vector3.new(7, 5, 10)
		incubator.Anchored = true
		incubator.Color = Color3.fromRGB(255, 210, 93)
		incubator.Material = Enum.Material.Neon
		incubator.Parent = base
	end)
	if incubatorCreated then
		print("DIAGNOSTIC: Created Incubator successfully.")
	else
		warn("DIAGNOSTIC: Failed to create Incubator", incubatorError)
	end

	local hydrant = Instance.new("Model")
	hydrant.Name = "FireHydrant"
	hydrant.Parent = base

	local hydrantBody = Instance.new("Part")
	hydrantBody.Name = "Body"
	hydrantBody.Shape = Enum.PartType.Cylinder
	hydrantBody.Size = Vector3.new(4, 2.4, 2.4)
	hydrantBody.CFrame = CFrame.new(15, 2, -14) * CFrame.Angles(0, 0, math.rad(90))
	hydrantBody.Anchored = true
	hydrantBody.Color = Color3.fromRGB(204, 38, 43)
	hydrantBody.Material = Enum.Material.Metal
	hydrantBody.Parent = hydrant
	hydrant.PrimaryPart = hydrantBody

	local hydrantTop = Instance.new("Part")
	hydrantTop.Name = "Top"
	hydrantTop.Shape = Enum.PartType.Ball
	hydrantTop.Size = Vector3.new(2.8, 1.4, 2.8)
	hydrantTop.Position = Vector3.new(15, 4.1, -14)
	hydrantTop.Anchored = true
	hydrantTop.Color = Color3.fromRGB(232, 55, 55)
	hydrantTop.Material = Enum.Material.Metal
	hydrantTop.Parent = hydrant

	local hydrantBase = Instance.new("Part")
	hydrantBase.Name = "Base"
	hydrantBase.Shape = Enum.PartType.Cylinder
	hydrantBase.Size = Vector3.new(0.8, 3.2, 3.2)
	hydrantBase.CFrame = CFrame.new(15, 0.45, -14) * CFrame.Angles(0, 0, math.rad(90))
	hydrantBase.Anchored = true
	hydrantBase.Color = Color3.fromRGB(155, 31, 35)
	hydrantBase.Material = Enum.Material.Metal
	hydrantBase.Parent = hydrant

	local refillPrompt = Instance.new("ProximityPrompt")
	refillPrompt.Name = "HydrantRefillPrompt"
	refillPrompt.ActionText = "Refill Water"
	refillPrompt.ObjectText = "Fire Hydrant"
	refillPrompt.KeyboardKeyCode = Enum.KeyCode.E
	refillPrompt.HoldDuration = 2
	refillPrompt.MaxActivationDistance = 10
	refillPrompt.RequiresLineOfSight = false
	refillPrompt.Parent = hydrantBody
end

-- Square half-stud pixels provide a much smoother silhouette than the former
-- coarse grid while remaining individually queryable by the cursor ray.
local DIRT_COLUMNS = 48
local DIRT_ROWS = 72

local function createDrivewayDirt(environment: Folder)
	local jobSites = ensureFolder(environment, "JobSites")
	replaceChild(jobSites, "Bench_1")

	local site = Instance.new("Model")
	site.Name = "Bench_1"
	site.Parent = jobSites

	local driveway = Instance.new("Part")
	driveway.Name = "Driveway"
	driveway.Size = Vector3.new(24, 1, 36)
	driveway.Position = Vector3.new(0, 0.5, -28)
	driveway.Anchored = true
	driveway.Color = Color3.fromRGB(126, 127, 124)
	driveway.Material = Enum.Material.Concrete
	driveway:SetAttribute("CleanableSurface", true)
	driveway:SetAttribute("JobID", "Bench_1")
	driveway:SetAttribute("DirtColumns", DIRT_COLUMNS)
	driveway:SetAttribute("DirtRows", DIRT_ROWS)
	driveway.Parent = site
	site.PrimaryPart = driveway

	-- Each seamless micro-part is directly queryable by the cursor ray. This
	-- avoids guessing the rotated/mirrored UV orientation of a SurfaceGui and
	-- guarantees that the pixel under the pointer is the pixel that is cleaned.
	local dirtPixels = Instance.new("Folder")
	dirtPixels.Name = "DirtPixels"
	dirtPixels.Parent = site
	local pixelWidth = driveway.Size.X / DIRT_COLUMNS
	local pixelDepth = driveway.Size.Z / DIRT_ROWS
	local pixelHeight = 0.035

	local random = Random.new(81427)
	for row = 1, DIRT_ROWS do
		for column = 1, DIRT_COLUMNS do
			local shade = random:NextInteger(-8, 8)
			local localX = -driveway.Size.X * 0.5 + (column - 0.5) * pixelWidth
			local localZ = -driveway.Size.Z * 0.5 + (row - 0.5) * pixelDepth
			local pixel = Instance.new("Part")
			pixel.Name = string.format("Pixel_%d_%d", row, column)
			pixel.Size = Vector3.new(pixelWidth + 0.015, pixelHeight, pixelDepth + 0.015)
			pixel.CFrame = driveway.CFrame * CFrame.new(
				localX,
				driveway.Size.Y * 0.5 + pixelHeight * 0.5 + 0.005,
				localZ
			)
			pixel.Anchored = true
			pixel.CanCollide = false
			pixel.CanTouch = false
			pixel.CanQuery = true
			pixel.CastShadow = false
			pixel.Material = Enum.Material.SmoothPlastic
			local stainRoll = random:NextNumber()
			local isAccent = stainRoll < 0.05
			if stainRoll < 0.018 then
				pixel.Color = Color3.fromRGB(78 + shade, 82 + shade, 31)
			elseif stainRoll < 0.032 then
				pixel.Color = Color3.fromRGB(70 + shade, 35, 58 + shade)
			elseif stainRoll < 0.05 then
				pixel.Color = Color3.fromRGB(93 + shade, 47, 23)
			else
				pixel.Color = Color3.fromRGB(39 + shade, 34 + math.floor(shade * 0.4), 29)
			end
			pixel.Transparency = if isAccent
				then random:NextNumber(0.36, 0.52)
				else random:NextNumber(0.02, 0.14)
			pixel:SetAttribute("OriginalTransparency", pixel.Transparency)
			pixel:SetAttribute("DirtPixel", true)
			pixel:SetAttribute("JobID", "Bench_1")
			pixel:SetAttribute("DirtRow", row)
			pixel:SetAttribute("DirtColumn", column)
			pixel.Parent = dirtPixels
			CollectionService:AddTag(pixel, "DirtSegment")
		end
	end
end

function DevEnvironmentSetup:Init()
	if initialized then
		return
	end
	initialized = true

	local terrainCleared, terrainError = pcall(function()
		Workspace.Terrain:Clear()
	end)
	if not terrainCleared then
		initialized = false
		warn(string.format("DevEnvironmentSetup could not clear Terrain: %s", tostring(terrainError)))
		return
	end

	local environment = ensureFolder(Workspace, "EnvironmentFixtures")
	createGrassBaseplate(environment)
	createInteractionFixtures(environment)
	createDrivewayDirt(environment)

	Workspace:SetAttribute("DevEnvironmentSetupStatus", "Ready")
	print("DevEnvironmentSetup: grass, shop, egg, and pixel-driveway fixtures are ready")
end

return DevEnvironmentSetup
