--!strict

print("DIAGNOSTIC: DevEnvironmentSetup script is RUNNING.")

-- Centralized development fixtures for testing jobs and pets. The shop desk
-- and fire hydrant are artist-authored Workspace models and are never cloned.

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

local function configurePersistentFixtures(environment: Folder)
	local success, creationError = pcall(function()
		-- Rojo owns Workspace.Baseplate so it is visible before Play. These
		-- assignments are a runtime fallback for places that have not resynced.
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate == nil or not baseplate:IsA("BasePart") then
			if baseplate then
				baseplate:Destroy()
			end
			baseplate = Instance.new("Part")
			baseplate.Name = "Baseplate"
			baseplate.Parent = Workspace
		end
		baseplate.Size = Vector3.new(2048, 20, 2048)
		baseplate.Position = Vector3.new(0, -10, 0)
		baseplate.Anchored = true
		baseplate.Color = Color3.fromRGB(99, 121, 57)
		baseplate.Material = Enum.Material.Grass
		baseplate.Locked = true

		-- Purge objects made by the obsolete interaction-fixture generator.
		local legacyBaseplate = environment:FindFirstChild("Baseplate")
		if legacyBaseplate then
			legacyBaseplate:Destroy()
		end
		local base = ensureFolder(environment, "Base")
		for _, legacyName in { "Computer", "FireHydrant", "WaterStation", "EggIncubator" } do
			local legacy = base:FindFirstChild(legacyName)
			if legacy then
				legacy:Destroy()
			end
		end
	end)
	if success then
		print("DIAGNOSTIC: Persistent grass baseplate configured; legacy shop and hydrant removed.")
	else
		warn("DIAGNOSTIC: Failed to configure persistent fixtures", creationError)
	end
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
	configurePersistentFixtures(environment)
	createDrivewayDirt(environment)

	Workspace:SetAttribute("DevEnvironmentSetupStatus", "Ready")
	print("DevEnvironmentSetup: persistent grass, egg, and job-test fixtures are ready")
end

return DevEnvironmentSetup
