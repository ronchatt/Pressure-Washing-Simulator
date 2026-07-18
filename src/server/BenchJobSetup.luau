--!strict

-- Converts the artist-authored brown/black Workspace.Bench into the first
-- production-shaped cleaning target. Geometry is inspected at runtime so the
-- Blender export may be a Model, MeshPart, or collection of BaseParts.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local BenchJobSetup = {}
local initialized = false

local JOB_ID = "Bench_1"
local DIRT_TAG = "DirtSegment"
local MAX_PATCHES = 1_800

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

local function isUsableBenchPart(part: BasePart): boolean
	local lowerName = string.lower(part.Name)
	return part.Transparency < 0.8
		and not string.find(lowerName, "hitbox", 1, true)
		and not string.find(lowerName, "collision", 1, true)
		and not string.find(lowerName, "invisible", 1, true)
end

local function benchAppearanceScore(candidate: Instance): number
	local score = 0
	local totalWeight = 0
	for _, part in getBaseParts(candidate) do
		if isUsableBenchPart(part) then
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

local function findProductionBench(): Instance?
	local candidates: {Instance} = {}
	for _, child in Workspace:GetChildren() do
		if child.Name == "Bench" and (#getBaseParts(child) > 0) then
			table.insert(candidates, child)
		end
	end

	table.sort(candidates, function(left, right)
		return benchAppearanceScore(left) > benchAppearanceScore(right)
	end)
	return candidates[1]
end

local function convertToJobSite(candidate: Instance, jobSites: Folder): Model
	local oldSite = jobSites:FindFirstChild(JOB_ID)
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
	site.Name = JOB_ID
	site:SetAttribute("JobID", JOB_ID)
	site:SetAttribute("CleanableJobModel", true)
	site:SetAttribute("SourceModelName", "Bench")

	local largestPart: BasePart? = nil
	local largestVolume = -1
	for _, part in getBaseParts(site) do
		if isUsableBenchPart(part) then
			part.Anchored = true
			part.CanQuery = true
			part:SetAttribute("JobID", JOB_ID)
			part:SetAttribute("BenchCleanableSurface", true)
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

local function scanExposedSurfaces(site: Model): ({SurfaceHit}, number)
	local boundingCFrame, boundingSize = site:GetBoundingBox()
	local half = boundingSize * 0.5
	local step = math.clamp(math.max(boundingSize.X, boundingSize.Y, boundingSize.Z) / 34, 0.22, 0.42)
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
				-- Coherent noise produces dirty chunks while leaving most of the
				-- original bench material clearly visible.
				if chunkNoise > 0.055 and detailNoise > -0.34 then
					local origin = boundingCFrame.Position
						+ worldNormal * (scan.N + 1.5)
						+ worldAxisA * a
						+ worldAxisB * b
					local result = Workspace:Raycast(origin, -worldNormal * (scan.N * 2 + 3), params)
					if result and result.Instance:IsA("BasePart") and isUsableBenchPart(result.Instance) then
						if result.Normal:Dot(worldNormal) > 0.3 then
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

local function createDirtPatches(site: Model, hits: {SurfaceHit}, step: number)
	local oldDirt = site:FindFirstChild("DirtPixels")
	if oldDirt then
		oldDirt:Destroy()
	end

	local dirtFolder = Instance.new("Folder")
	dirtFolder.Name = "DirtPixels"
	dirtFolder.Parent = site
	local random = Random.new(731_041)

	for index, hit in hits do
		local patch = Instance.new("Part")
		patch.Name = string.format("BenchPatch_%04d", index)
		-- Thin overlapping elliptical discs form continuous organic grime blobs
		-- without the visibly raised square-tile appearance.
		patch.Shape = Enum.PartType.Cylinder
		patch.Size = Vector3.new(
			0.008,
			step * random:NextNumber(1.25, 2.05),
			step * random:NextNumber(1.05, 1.8)
		)
		local reference = if math.abs(hit.Normal:Dot(Vector3.yAxis)) > 0.92 then Vector3.zAxis else Vector3.yAxis
		local tangent = (reference - hit.Normal * reference:Dot(hit.Normal)).Unit
		tangent = CFrame.fromAxisAngle(hit.Normal, random:NextNumber(-math.pi, math.pi)):VectorToWorldSpace(tangent)
		local secondTangent = hit.Normal:Cross(tangent).Unit
		patch.CFrame = CFrame.fromMatrix(
			hit.Position + hit.Normal * 0.006,
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

		local accent = random:NextNumber()
		if accent < 0.018 then
			patch.Color = Color3.fromRGB(55, 59, 28)
			patch.Transparency = random:NextNumber(0.46, 0.6)
		elseif accent < 0.032 then
			patch.Color = Color3.fromRGB(49, 29, 44)
			patch.Transparency = random:NextNumber(0.45, 0.58)
		elseif accent < 0.05 then
			patch.Color = Color3.fromRGB(73, 39, 22)
			patch.Transparency = random:NextNumber(0.42, 0.56)
		else
			local shade = random:NextInteger(-7, 7)
			patch.Color = Color3.fromRGB(36 + shade, 31 + math.floor(shade * 0.45), 26)
			patch.Transparency = random:NextNumber(0.12, 0.3)
		end

		patch:SetAttribute("DirtPixel", true)
		patch:SetAttribute("DirtPatch", true)
		patch:SetAttribute("JobID", JOB_ID)
		patch:SetAttribute("OriginalTransparency", patch.Transparency)
		patch:SetAttribute("SourcePart", hit.Source:GetFullName())
		patch.Parent = dirtFolder
		CollectionService:AddTag(patch, DIRT_TAG)
	end
	site:SetAttribute("DirtPatchCount", #hits)
end

function BenchJobSetup:Init()
	if initialized then
		return
	end
	initialized = true

	local candidate = findProductionBench()
	if candidate == nil then
		warn("BenchJobSetup: no direct Workspace.Bench candidate was found; keeping the development driveway.")
		return
	end

	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
	if jobSites == nil or not jobSites:IsA("Folder") then
		warn("BenchJobSetup: EnvironmentFixtures.JobSites is unavailable.")
		return
	end

	local site = convertToJobSite(candidate, jobSites)
	local hits, step = scanExposedSurfaces(site)
	if #hits == 0 then
		warn("BenchJobSetup: the selected bench produced no exposed dirt locations.")
		return
	end
	createDirtPatches(site, hits, step)
	print(string.format(
		"BenchJobSetup: connected the brown/black bench to %s with %d dirty validation patches.",
		JOB_ID,
		#hits
	))
end

return BenchJobSetup
