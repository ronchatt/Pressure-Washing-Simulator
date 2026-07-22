--!strict

-- Converts artist-authored Workspace job objects into
-- geometry-aware cleaning targets. Blender exports may be Models, MeshParts,
-- or collections of BaseParts; exposed surfaces are discovered at runtime.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SharedJobData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedJobData"))

local BenchJobSetup = {}
local initialized = false

local DIRT_TAG = "DirtSegment"
local MAX_PATCHES = 1_800
local MUD_TEXTURE_ID = "rbxassetid://140256621594007"
local DRIVEWAY_DIRT_PALETTE = {
	Color3.fromRGB(126, 95, 58), -- dried mud
	Color3.fromRGB(112, 91, 65), -- dusty earth
	Color3.fromRGB(139, 105, 62), -- clay-brown
	Color3.fromRGB(100, 112, 67), -- mossy green
	Color3.fromRGB(137, 82, 51), -- rusty grime
	Color3.fromRGB(122, 109, 75), -- stale ochre
	Color3.fromRGB(143, 124, 74), -- sickly yellow-brown
	Color3.fromRGB(91, 105, 66), -- mildew green
}
local DRIVEWAY_STUBBORN_PALETTE = {
	Color3.fromRGB(79, 58, 39),
	Color3.fromRGB(73, 68, 43),
	Color3.fromRGB(69, 79, 45),
	Color3.fromRGB(91, 52, 38),
}
local DRIVEWAY_EARTH_INDICES = { 1, 2, 3, 6 }

type JobConfig = {
	SourceName: string,
	JobID: string,
	JobType: string,
	RandomSeed: number,
	PreferDarkest: boolean,
	ExteriorOnly: boolean?,
	MaxExteriorDepth: number?,
	MinimumHeightFraction: number?,
	MinimumWorldY: number?,
	ScanStep: number?,
	PatchScale: number?,
	NoiseThreshold: number?,
	ClusterScale: number?,
	ClusterThreshold: number?,
	VisualTransparencyMin: number?,
	VisualTransparencyMax: number?,
	LiquidCanvas: boolean?,
	FastFadeDuration: number?,
	CleanPowerMultiplier: number?,
	ResistanceMultiplier: number?,
	TopSurfaceOnly: boolean?,
	ContinuousCoverage: boolean?,
	StyleAsConcrete: boolean?,
}

local JOB_CONFIGS: {JobConfig} = {
	{
		SourceName = "Bench",
		JobID = "Bench_1",
		JobType = "Bench",
		RandomSeed = 731_041,
		PreferDarkest = true,
		FastFadeDuration = 0.13,
		CleanPowerMultiplier = 0.8,
		ResistanceMultiplier = 1.5,
	},
	{
		SourceName = "Fence",
		JobID = "Fence_1",
		JobType = "Fence",
		RandomSeed = 918_227,
		PreferDarkest = false,
		FastFadeDuration = 0.055,
		CleanPowerMultiplier = 1.7,
	},
	{
		SourceName = "Stationary car",
		JobID = "Car_1",
		JobType = "Car",
		RandomSeed = 482_771,
		PreferDarkest = false,
		ExteriorOnly = true,
		MaxExteriorDepth = 4,
		MinimumHeightFraction = 0.12,
		MinimumWorldY = 0.6,
		ScanStep = 0.5,
		PatchScale = 0.82,
		NoiseThreshold = -0.08,
		ClusterScale = 0.22,
		ClusterThreshold = -0.12,
		VisualTransparencyMin = 0.12,
		VisualTransparencyMax = 0.3,
		FastFadeDuration = 0.22,
		CleanPowerMultiplier = 1.5,
		ResistanceMultiplier = 1.15,
		LiquidCanvas = true,
	},
	{
		SourceName = "Driveway",
		JobID = "Driveway_1",
		JobType = "Driveway",
		RandomSeed = 347_119,
		PreferDarkest = false,
		TopSurfaceOnly = true,
		ContinuousCoverage = true,
		StyleAsConcrete = true,
		ScanStep = 0.88,
		PatchScale = 1,
		VisualTransparencyMin = 0.38,
		VisualTransparencyMax = 0.53,
		FastFadeDuration = 0.12,
		CleanPowerMultiplier = 1.55,
		LiquidCanvas = true,
	},
	{
		SourceName = "house1",
		JobID = "SingleStoryHouse_1",
		JobType = "House",
		RandomSeed = 604_913,
		PreferDarkest = false,
		ExteriorOnly = true,
		MaxExteriorDepth = 14,
		ScanStep = 0.72,
		PatchScale = 0.68,
		NoiseThreshold = -0.06,
		ClusterScale = 0.16,
		ClusterThreshold = 0,
		VisualTransparencyMin = 0.25,
		VisualTransparencyMax = 0.5,
		LiquidCanvas = true,
	},
}

type SurfaceHit = {
	Position: Vector3,
	Normal: Vector3,
	Source: BasePart,
	Noise: number,
}

local function getBaseParts(candidate: Instance): {BasePart}
	local parts: {BasePart} = {}
	if candidate:IsA("BasePart") then
		table.insert(parts, candidate)
	end
	for _, descendant in candidate:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function isUsableSurfacePart(part: BasePart): boolean
	local lowerName = string.lower(part.Name)
	return part.Transparency < 0.8
		and not string.find(lowerName, "hitbox", 1, true)
		and not string.find(lowerName, "collision", 1, true)
		and not string.find(lowerName, "invisible", 1, true)
end

local function appearanceScore(candidate: Instance): number
	local score = 0
	local totalWeight = 0
	for _, part in getBaseParts(candidate) do
		if isUsableSurfacePart(part) then
			local size = part.Size
			local weight = math.max(0.05, size.X * size.Y * size.Z)
			local color = part.Color
			local brightness = (color.R + color.G + color.B) / 3
			local brownness = math.max(0, color.R - color.B) + math.max(0, color.G - color.B) * 0.25
			local darkness = 1 - brightness
			local texturedBonus = 0
			if part:IsA("MeshPart") and part.TextureID ~= "" then
				texturedBonus = 0.35
			elseif part:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil
				or part:FindFirstChildWhichIsA("Texture") ~= nil
				or part:FindFirstChildWhichIsA("Decal") ~= nil
			then
				texturedBonus = 0.25
			end
			score += weight * (darkness + brownness * 0.8 + texturedBonus)
			totalWeight += weight
		end
	end
	return if totalWeight > 0 then score / totalWeight else -math.huge
end

local function findProductionCandidate(config: JobConfig): Instance?
	local candidates: {Instance} = {}
	for _, child in Workspace:GetChildren() do
		if child.Name == config.SourceName and (#getBaseParts(child) > 0) then
			table.insert(candidates, child)
		end
	end

	table.sort(candidates, function(left, right)
		if config.PreferDarkest then
			return appearanceScore(left) > appearanceScore(right)
		end
		return #getBaseParts(left) > #getBaseParts(right)
	end)
	return candidates[1]
end

local function convertToJobSite(candidate: Instance, jobSites: Folder, config: JobConfig): Model
	local poolID = candidate:GetAttribute("JobPoolID")
	local oldSite = jobSites:FindFirstChild(config.JobID)
	if oldSite then
		oldSite:Destroy()
	end

	local site: Model
	if candidate:IsA("Model") then
		site = candidate
		site.Parent = jobSites
	else
		site = Instance.new("Model")
		site.Parent = jobSites
		candidate.Parent = site
	end
	site.Name = config.JobID
	site:SetAttribute("JobID", config.JobID)
	site:SetAttribute("JobType", config.JobType)
	if typeof(poolID) == "string" and poolID ~= "" then
		site:SetAttribute("JobPoolID", poolID)
		-- Pooled physical locations stay out of the phone catalog. The shared
		-- contract selects one of them when the player accepts the job.
		site:SetAttribute("PhoneJobEnabled", false)
	else
		site:SetAttribute("PhoneJobEnabled", true)
	end
	site:SetAttribute("CleanableJobModel", true)
	site:SetAttribute("SourceModelName", config.SourceName)
	local templateID = if typeof(poolID) == "string" and poolID ~= "" then poolID else config.JobID
	local template = SharedJobData.Jobs[templateID]
	local function setMetadata(name: string, fallback: any)
		if site:GetAttribute(name) == nil and fallback ~= nil then
			site:SetAttribute(name, fallback)
		end
	end
	setMetadata("DisplayName", template and template.DisplayName or config.SourceName)
	setMetadata("RequiredTier", template and template.RequiredTier or "Benches")
	setMetadata("Difficulty", template and template.Difficulty or "Easy")
	setMetadata("RecommendedWasher", template and template.RecommendedWasher or "Basic Backpack")
	setMetadata("Reward", template and template.Reward or 50)
	setMetadata("CompletionThreshold", template and template.CompletionThreshold or 95)

	local largestPart: BasePart? = nil
	local largestVolume = -1
	for _, part in getBaseParts(site) do
		if isUsableSurfacePart(part) then
			part.Anchored = true
			part.CanQuery = true
			if config.StyleAsConcrete then
				part.Material = Enum.Material.Concrete
				part.Color = Color3.fromRGB(151, 143, 130)
				part.Reflectance = 0
			end
			part:SetAttribute("JobID", config.JobID)
			part:SetAttribute("Cleanable3DSurface", true)
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > largestVolume then
				largestVolume = volume
				largestPart = part
			end
		end
	end
	if site.PrimaryPart == nil then
		site.PrimaryPart = largestPart
	end
	return site
end

local function scanExposedSurfaces(site: Model, config: JobConfig): ({SurfaceHit}, number)
	local boundingCFrame, boundingSize = site:GetBoundingBox()
	local half = boundingSize * 0.5
	-- Larger logical regions reduce the visible tiled pattern. Each region gets
	-- layered lobes below, preserving fine cleaning without hundreds of obvious
	-- circular dots.
	local step = config.ScanStep
		or math.clamp(math.max(boundingSize.X, boundingSize.Y, boundingSize.Z) / 27, 0.27, 0.48)
	local hits: {SurfaceHit} = {}
	local occupied: {[string]: boolean} = {}

	-- Bottom-facing surfaces are intentionally omitted. The other five scans
	-- naturally reach the seat, back, legs, supports, and exposed ledges.
	local scans = {
		{ Normal = Vector3.new(0, 1, 0), AxisA = Vector3.new(1, 0, 0), AxisB = Vector3.new(0, 0, 1), N = half.Y, A = half.X, B = half.Z },
		{ Normal = Vector3.new(0, 0, 1), AxisA = Vector3.new(1, 0, 0), AxisB = Vector3.new(0, 1, 0), N = half.Z, A = half.X, B = half.Y },
		{ Normal = Vector3.new(0, 0, -1), AxisA = Vector3.new(-1, 0, 0), AxisB = Vector3.new(0, 1, 0), N = half.Z, A = half.X, B = half.Y },
		{ Normal = Vector3.new(1, 0, 0), AxisA = Vector3.new(0, 0, -1), AxisB = Vector3.new(0, 1, 0), N = half.X, A = half.Z, B = half.Y },
		{ Normal = Vector3.new(-1, 0, 0), AxisA = Vector3.new(0, 0, 1), AxisB = Vector3.new(0, 1, 0), N = half.X, A = half.Z, B = half.Y },
	}
	if config.TopSurfaceOnly then
		scans = { scans[1] }
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { site }
	params.IgnoreWater = true

	for faceIndex, scan in scans do
		local worldNormal = boundingCFrame:VectorToWorldSpace(scan.Normal)
		local worldAxisA = boundingCFrame:VectorToWorldSpace(scan.AxisA)
		local worldAxisB = boundingCFrame:VectorToWorldSpace(scan.AxisB)
		for a = -scan.A + step * 0.5, scan.A - step * 0.5, step do
			for b = -scan.B + step * 0.5, scan.B - step * 0.5, step do
				local chunkNoise = math.noise(a * 0.72 + faceIndex * 11, b * 0.72 - faceIndex * 7, faceIndex * 2.9)
				local detailNoise = math.noise(a * 2.1 - 19, b * 2.1 + 31, faceIndex * 5.3)
				local clusterNoise = if config.ClusterScale
					then math.noise(
						a * config.ClusterScale + faceIndex * 4.7,
						b * config.ClusterScale - faceIndex * 3.1,
						faceIndex * 1.9
					)
					else 1
				-- Coherent noise produces dirty chunks while leaving most of the
				-- original bench material clearly visible.
				if config.ContinuousCoverage
					or (clusterNoise > (config.ClusterThreshold or -math.huge)
					and chunkNoise > (config.NoiseThreshold or 0.055)
					and detailNoise > -0.34)
				then
					-- Break the visible sampling grid without destroying the larger
					-- coherent noise clusters. Every offset is deterministic.
					local jitterStrength = if config.ContinuousCoverage then 0.92 else 0.34
					local jitterA = math.noise(a * 3.7, b * 2.9, faceIndex * 17) * step * jitterStrength
					local jitterB = math.noise(a * 2.6 + 41, b * 4.1 - 23, faceIndex * 13) * step * jitterStrength
					local origin = boundingCFrame.Position
						+ worldNormal * (scan.N + 1.5)
						+ worldAxisA * (a + jitterA)
						+ worldAxisB * (b + jitterB)
					local result = Workspace:Raycast(origin, -worldNormal * (scan.N * 2 + 3), params)
					if result and result.Instance:IsA("BasePart") and isUsableSurfacePart(result.Instance) then
						local validSurface = result.Normal:Dot(worldNormal) > 0.3
						if validSurface and config.ExteriorOnly then
							-- house1 is a single combined MeshPart, so exterior filtering
							-- must be geometric rather than name-based. Never place grime
							-- on downward-facing roof/deck undersides.
							if result.Normal.Y < -0.08 then
								validSurface = false
							end

							-- Vehicles can expose horizontal faces inside wheel wells or
							-- underneath the chassis during side scans. Keep dirt above a
							-- small fraction of the model's bottom so only player-visible
							-- bodywork participates in the job.
							if validSurface and config.MinimumHeightFraction ~= nil then
								local minimumY = boundingCFrame.Position.Y
									- half.Y
									+ boundingSize.Y * config.MinimumHeightFraction
								if result.Position.Y < minimumY then
									validSurface = false
								end
							end
							if validSurface and config.MinimumWorldY ~= nil and result.Position.Y < config.MinimumWorldY then
								validSurface = false
							end

							-- Horizontal scans may travel through doors, windows, porch
							-- openings, or roof overhangs. Deep hits are not part of the
							-- immediately reachable exterior shell.
							if validSurface and faceIndex > 1 then
								local exteriorDepth = math.max(0, (origin - result.Position).Magnitude - 1.5)
								if exteriorDepth > (config.MaxExteriorDepth or 6) then
									validSurface = false
								end
							end

							-- Require clear space immediately in front of the candidate.
							-- This rejects concave faces tucked beneath patio or roof
							-- geometry even when their normals point partly outward.
							if validSurface and result.Normal.Y < 0.3 then
								local clearanceHit = Workspace:Raycast(
									result.Position + result.Normal * 0.04,
									result.Normal * 2.25,
									params
								)
								if clearanceHit ~= nil then
									validSurface = false
								end
							end
						end

						if validSurface then
							local quantize = step * 0.7
							local key = string.format(
								"%d:%d:%d",
								math.round(result.Position.X / quantize),
								math.round(result.Position.Y / quantize),
								math.round(result.Position.Z / quantize)
							)
							if not occupied[key] then
								occupied[key] = true
								table.insert(hits, {
									Position = result.Position,
									Normal = result.Normal,
									Source = result.Instance,
									Noise = chunkNoise,
								})
								if #hits >= MAX_PATCHES then
									return hits, step
								end
							end
						end
					end
				end
			end
		end
	end
	return hits, step
end

local function createDirtPatches(site: Model, hits: {SurfaceHit}, step: number, config: JobConfig)
	local oldDirt = site:FindFirstChild("DirtPixels")
	if oldDirt then
		oldDirt:Destroy()
	end

	local dirtFolder = Instance.new("Folder")
	dirtFolder.Name = "DirtPixels"
	dirtFolder.Parent = site
	local random = Random.new(config.RandomSeed)
	local patchScale = config.PatchScale or 1
	site:SetAttribute("UsesLiquidDirtCanvas", config.LiquidCanvas == true)

	for index, hit in hits do
		local patch = Instance.new("Part")
		patch.Name = string.format("MudBlob_%04d", index)
		-- The Part is an invisible query/validation plane. Only its transparent
		-- irregular splatter Decal is rendered, so no geometric circle or square
		-- is visible to the player.
		local macroNoise = math.noise(hit.Position.X * 0.035, hit.Position.Z * 0.035, config.RandomSeed * 0.00007)
		local stainNoise = math.noise(hit.Position.X * 0.13 + 17, hit.Position.Z * 0.13 - 29, config.RandomSeed * 0.00013)
		local sizeVariation = math.clamp(1 + macroNoise * 0.7 + stainNoise * 0.25, 0.68, 1.42)
		local widthScale = if config.ContinuousCoverage
			then random:NextNumber(0.95, 2.25) * sizeVariation
			elseif config.PatchScale
			then random:NextNumber(0.65, 2.4)
			else random:NextNumber(2.05, 3.25)
		local heightScale = if config.ContinuousCoverage
			then random:NextNumber(0.9, 2.15) * math.clamp(2 - sizeVariation, 0.72, 1.32)
			elseif config.PatchScale
			then random:NextNumber(0.5, 2)
			else random:NextNumber(1.7, 2.85)
		patch.Size = Vector3.new(0.004, step * widthScale * patchScale, step * heightScale * patchScale)
		local reference = if math.abs(hit.Normal:Dot(Vector3.yAxis)) > 0.92 then Vector3.zAxis else Vector3.yAxis
		local tangent = (reference - hit.Normal * reference:Dot(hit.Normal)).Unit
		tangent = CFrame.fromAxisAngle(hit.Normal, random:NextNumber(-math.pi, math.pi)):VectorToWorldSpace(tangent)
		local secondTangent = hit.Normal:Cross(tangent).Unit
		patch.CFrame = CFrame.fromMatrix(
			hit.Position + hit.Normal * 0.003,
			hit.Normal,
			tangent,
			secondTangent
		)
		patch.Anchored = true
		patch.CanCollide = false
		patch.CanTouch = false
		patch.CanQuery = true
		patch.CastShadow = false
		patch.Material = Enum.Material.SmoothPlastic
		patch.Transparency = 1

		patch:SetAttribute("DirtPixel", true)
		patch:SetAttribute("DirtPatch", true)
		patch:SetAttribute("JobID", config.JobID)
		-- Thicker-looking dark pockets take slightly longer to dislodge. The
		-- client combines this with its distance pressure falloff.
		local stubbornNoise = math.noise(hit.Position.X * 0.085, hit.Position.Z * 0.085, config.RandomSeed * 0.0001)
		local isStubborn = config.ContinuousCoverage == true and stubbornNoise > 0.16
		local resistanceMultiplier = config.ResistanceMultiplier or 1
		patch:SetAttribute(
			"DirtResistance",
			(if isStubborn then random:NextNumber(1.75, 2.35) else random:NextNumber(0.88, 1.16))
				* resistanceMultiplier
		)
		patch:SetAttribute("StubbornDirt", isStubborn)
		patch:SetAttribute("DirtWeight", math.clamp(patch.Size.Y * patch.Size.Z / (step * step), 1, 7))
		patch:SetAttribute("OriginalTransparency", 1)
		patch:SetAttribute("SourcePart", hit.Source:GetFullName())
		if config.FastFadeDuration ~= nil then
			patch:SetAttribute("FastFadeDuration", config.FastFadeDuration)
		end
		if config.CleanPowerMultiplier ~= nil then
			patch:SetAttribute("CleanPowerMultiplier", config.CleanPowerMultiplier)
		end
		patch.Parent = dirtFolder

		if not config.LiquidCanvas then
			local mudVisual = Instance.new("Decal")
			mudVisual.Name = "MudVisual"
			mudVisual.Face = Enum.NormalId.Right
			mudVisual.Texture = MUD_TEXTURE_ID
			if config.ContinuousCoverage then
				local palette = if isStubborn then DRIVEWAY_STUBBORN_PALETTE else DRIVEWAY_DIRT_PALETTE
				local paletteIndex: number
				if isStubborn then
					paletteIndex = random:NextInteger(1, #palette)
				elseif macroNoise < -0.2 then
					paletteIndex = if stainNoise > 0 then 4 else 8 -- moss/mildew zone
				elseif macroNoise > 0.24 then
					paletteIndex = if stainNoise > 0.08 then 5 else 3 -- rust/clay zone
				elseif stainNoise > 0.25 then
					paletteIndex = 7 -- small ochre pockets
				else
					paletteIndex = DRIVEWAY_EARTH_INDICES[random:NextInteger(1, #DRIVEWAY_EARTH_INDICES)]
				end
				local baseColor = palette[paletteIndex]
				local tint = random:NextInteger(-5, 5) / 255
				mudVisual.Color3 = Color3.new(
					math.clamp(baseColor.R + tint, 0, 1),
					math.clamp(baseColor.G + tint, 0, 1),
					math.clamp(baseColor.B + tint, 0, 1)
				)
				mudVisual.Transparency = if isStubborn
					then math.clamp(random:NextNumber(0.22, 0.4) + macroNoise * 0.08, 0.18, 0.48)
					else math.clamp(
						random:NextNumber(
							config.VisualTransparencyMin or 0.18,
							config.VisualTransparencyMax or 0.34
						) + macroNoise * 0.16 + stainNoise * 0.1,
						0.28,
						0.68
					)
			else
				local tint = random:NextInteger(-12, 12)
				mudVisual.Color3 = Color3.fromRGB(174 + tint, 151 + tint, 119 + tint)
				mudVisual.Transparency = random:NextNumber(
					config.VisualTransparencyMin or 0.18,
					config.VisualTransparencyMax or 0.34
				)
			end
			mudVisual:SetAttribute("DirtVisual", true)
			mudVisual:SetAttribute("OriginalTransparency", mudVisual.Transparency)
			mudVisual.Parent = patch
		end
		CollectionService:AddTag(patch, DIRT_TAG)
	end
	site:SetAttribute("DirtPatchCount", #hits)
end

local function deterministicSeed(value: string): number
	local hash = 17
	for index = 1, #value do
		hash = (hash * 31 + string.byte(value, index)) % 2_000_000_000
	end
	return hash
end

local function getPreset(jobType: string): JobConfig?
	local requestedType = if jobType == "Mansion" then "House" else jobType
	for _, config in JOB_CONFIGS do
		if config.JobType == requestedType then
			return config
		end
	end
	return nil
end

local function makeAuthoredConfig(candidate: Instance, jobID: string, jobType: string): JobConfig?
	local preset = getPreset(jobType)
	if preset == nil then
		return nil
	end
	local config = table.clone(preset) :: any
	config.SourceName = candidate.Name
	config.JobID = jobID
	config.JobType = jobType
	config.RandomSeed = deterministicSeed(jobID)
	return config :: JobConfig
end

local function collectAuthoredCandidates(): {Instance}
	local candidates: {Instance} = {}
	for _, candidate in Workspace:GetDescendants() do
		if (candidate:IsA("Model") or candidate:IsA("BasePart"))
			and (candidate:GetAttribute("PhoneJobEnabled") == true
				or CollectionService:HasTag(candidate, "CleanableJobSite"))
		then
			local environment = Workspace:FindFirstChild("EnvironmentFixtures")
			local runtimeSites = environment and environment:FindFirstChild("JobSites")
			if runtimeSites and candidate:IsDescendantOf(runtimeSites) then
				continue
			end
			local parentCandidate = candidate.Parent
			local nested = false
			while parentCandidate and parentCandidate ~= Workspace do
				if parentCandidate:GetAttribute("PhoneJobEnabled") == true
					or CollectionService:HasTag(parentCandidate, "CleanableJobSite")
				then
					nested = true
					break
				end
				parentCandidate = parentCandidate.Parent
			end
			if not nested then
				table.insert(candidates, candidate)
			end
		end
	end
	return candidates
end

local function connectCandidate(candidate: Instance, jobSites: Folder, config: JobConfig): boolean
	local site = convertToJobSite(candidate, jobSites, config)
	local hits, step = scanExposedSurfaces(site, config)
	if #hits == 0 then
		warn(string.format("Job authoring: %s produced no exposed dirt locations.", config.JobID))
		return false
	end
	createDirtPatches(site, hits, step, config)
	print(string.format(
		"SurfaceJobSetup: connected %s to %s (%s) with %d muddy validation regions.",
		config.SourceName,
		config.JobID,
		config.JobType,
		#hits
	))
	return true
end

function BenchJobSetup:Init()
	if initialized then
		return
	end
	initialized = true

	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
	if jobSites == nil or not jobSites:IsA("Folder") then
		warn("BenchJobSetup: EnvironmentFixtures.JobSites is unavailable.")
		return
	end

	local authoredCandidates = collectAuthoredCandidates()
	for _, config in JOB_CONFIGS do
		local candidate = findProductionCandidate(config)
		if candidate == nil then
			warn(string.format(
				"BenchJobSetup: no direct Workspace.%s candidate was found; %s was not connected.",
				config.SourceName,
				config.JobID
			))
			continue
		end

		connectCandidate(candidate, jobSites, config)
	end

	local seenJobIDs: {[string]: boolean} = {}
	for _, child in jobSites:GetChildren() do
		local jobID = child:GetAttribute("JobID")
		if typeof(jobID) == "string" then seenJobIDs[jobID] = true end
	end
	for _, candidate in authoredCandidates do
		local jobID = candidate:GetAttribute("JobID")
		local jobType = candidate:GetAttribute("JobType")
		if typeof(jobID) ~= "string" or jobID == "" or not string.match(jobID, "^[%w_%-]+$") then
			warn(string.format("Job authoring: %s needs a unique alphanumeric JobID attribute.", candidate:GetFullName()))
			continue
		end
		if seenJobIDs[jobID] then
			warn(string.format("Job authoring: duplicate JobID '%s' on %s; skipped.", jobID, candidate:GetFullName()))
			continue
		end
		if typeof(jobType) ~= "string" then
			warn(string.format("Job authoring: %s needs a JobType attribute.", candidate:GetFullName()))
			continue
		end
		local config = makeAuthoredConfig(candidate, jobID, jobType)
		if config == nil then
			warn(string.format(
				"Job authoring: unsupported JobType '%s' on %s. Use Bench, Fence, Car, Driveway, House, or Mansion.",
				jobType,
				candidate:GetFullName()
			))
			continue
		end
		if connectCandidate(candidate, jobSites, config) then
			seenJobIDs[jobID] = true
		end
	end
end

return BenchJobSetup
