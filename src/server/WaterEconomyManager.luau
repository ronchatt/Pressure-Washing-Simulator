--!strict

-- Server-authoritative refill economy. Clients choose an authored source, but
-- this module resolves that source itself and validates distance, cash, tank
-- state, and active-job ownership before changing profile data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local JobManager = require(script.Parent:WaitForChild("JobManager"))
local MonetizationManager = require(script.Parent:WaitForChild("MonetizationManager"))
local shared = ReplicatedStorage:WaitForChild("Shared")
local SharedWaterData = require(shared:WaitForChild("SharedWaterData"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaterRefillRequest = remotes:WaitForChild("WaterRefillRequest") :: RemoteEvent
local WaterRefillResult = remotes:WaitForChild("WaterRefillResult") :: RemoteEvent

local WaterEconomyManager = {}
local initialized = false
local requestCooldown: {[Player]: number} = {}

local function findInteractionPart(instance: Instance?): BasePart?
	if instance == nil then return nil end
	if instance:IsA("BasePart") then return instance end
	if instance:IsA("Model") then return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true) end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getJobSite(jobID: string): Instance?
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local runtimeSites = environment and environment:FindFirstChild("JobSites")
	return (runtimeSites and runtimeSites:FindFirstChild(jobID)) or Workspace:FindFirstChild(jobID, true)
end

local function getBaseWaterPart(): BasePart?
	local artistBase = Workspace:FindFirstChild("Base")
	local artistWater = artistBase and artistBase:FindFirstChild("Water refill", true)
	if artistWater ~= nil then
		return findInteractionPart(artistWater)
	end
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local fallbackBase = environment and environment:FindFirstChild("Base")
	return findInteractionPart(fallbackBase and fallbackBase:FindFirstChild("WaterStation"))
end

local function getHydrantParts(): {BasePart}
	local hydrants: {BasePart} = {}
	local seen: {[BasePart]: boolean} = {}
	for _, candidate in Workspace:GetDescendants() do
		local marked = candidate:GetAttribute("HydrantWaterSource") == true
		local legacy = candidate.Name == "Fire Hydrant" and candidate.Parent == Workspace
		if marked or legacy then
			local part = findInteractionPart(candidate)
			if part and not seen[part] then
				seen[part] = true
				table.insert(hydrants, part)
			end
		end
	end
	return hydrants
end

local function getNearestHydrant(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, hydrant in getHydrantParts() do
		local distance = if root and root:IsA("BasePart") then (root.Position - hydrant.Position).Magnitude else 0
		if distance < bestDistance then
			best = hydrant
			bestDistance = distance
		end
	end
	return best
end

local function getSource(refillType: string, player: Player): (BasePart?, string?)
	if refillType == "Base" then
		return getBaseWaterPart(), nil
	elseif refillType == "Hydrant" then
		return getNearestHydrant(player), nil
	elseif refillType == "Customer" then
		local activeJob = JobManager:GetActiveJob(player)
		if activeJob == nil then return nil, "Accept a job before using customer water." end
		return findInteractionPart(getJobSite(activeJob.CurrentTargetJobID or activeJob.IncludedJobIDs[1])), nil
	end
	return nil, "Unknown water source."
end

local function createPrompt(parent: BasePart, name: string, refillType: string, objectText: string, jobID: string?)
	local existing = parent:FindFirstChild(name)
	local prompt: ProximityPrompt
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
	else
		if existing then existing:Destroy() end
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.Parent = parent
	end
	prompt.ActionText = if refillType == "Customer" then "Use Customer Water" else "Refill Water"
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = if refillType == "Hydrant" then 2 else 0.65
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Style = if refillType == "Customer" then Enum.ProximityPromptStyle.Custom else Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("RefillType", refillType)
	if jobID then prompt:SetAttribute("JobID", jobID) end
end

local function setupPrompts()
	local basePart = getBaseWaterPart()
	if basePart then
		createPrompt(basePart, "BaseRefillPrompt", "Base", "Base Tank Refill")
	else
		warn("WaterEconomyManager could not find Workspace.Base['Water refill']")
	end
	for _, hydrant in getHydrantParts() do
		createPrompt(hydrant, "HydrantRefillPrompt", "Hydrant", "City Fire Hydrant")
	end
	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local runtimeSites = environment and environment:FindFirstChild("JobSites")
	for _, site in if runtimeSites then runtimeSites:GetChildren() else {} do
		local jobID = site:GetAttribute("JobID")
		local sitePart = findInteractionPart(site)
		if sitePart then
			createPrompt(sitePart, "CustomerWaterPrompt", "Customer", tostring(jobID or site.Name), if typeof(jobID) == "string" then jobID else nil)
		end
	end
end

local function respond(player: Player, success: boolean, message: string, refillType: string)
	local data = DataManager:GetData(player)
	WaterRefillResult:FireClient(player, {
		Success = success,
		Message = message,
		RefillType = refillType,
		Water = data and data.Water or 0,
		MaxWater = data and data.MaxWater or 0,
	})
end

local function handleRefill(player: Player, refillType: string)
	local now = os.clock()
	if requestCooldown[player] and now - requestCooldown[player] < 0.5 then return end
	requestCooldown[player] = now
	local config = SharedWaterData.RefillTypes[refillType]
	if config == nil then respond(player, false, "Unknown water source.", refillType); return end
	if MonetizationManager:OwnsInfiniteWater(player) then respond(player, false, "Infinite Water is already active.", refillType); return end
	local data = DataManager:GetData(player)
	if data == nil then respond(player, false, "Player data is still loading.", refillType); return end
	if data.Water >= data.MaxWater - 0.001 then respond(player, false, "Your tank is already full.", refillType); return end
	local source, sourceError = getSource(refillType, player)
	if source == nil then respond(player, false, sourceError or "Water source unavailable.", refillType); return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local distance = math.huge
	if root and root:IsA("BasePart") then
		local localPosition = source.CFrame:PointToObjectSpace(root.Position)
		local halfSize = source.Size * 0.5
		local closestLocal = Vector3.new(
			math.clamp(localPosition.X, -halfSize.X, halfSize.X),
			math.clamp(localPosition.Y, -halfSize.Y, halfSize.Y),
			math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
		)
		distance = (root.Position - source.CFrame:PointToWorldSpace(closestLocal)).Magnitude
	end
	if distance > SharedWaterData.MaxInteractionDistance then
		respond(player, false, "Move closer to the water source.", refillType)
		return
	end
	if refillType == "Customer" then
		local activeJob = JobManager:GetActiveJob(player)
		local promptJobID = source:GetAttribute("JobID")
		if activeJob == nil or (typeof(promptJobID) == "string" and not activeJob.IncludedLookup[promptJobID]) then
			respond(player, false, "This water supply does not belong to your active job.", refillType)
			return
		end
		if not JobManager:UseCustomerWater(player, config.CustomerPayCut) then
			respond(player, false, "No active job was found.", refillType)
			return
		end
	elseif config.CashCost > 0 and not DataManager:DeductCash(player, config.CashCost) then
		respond(player, false, string.format("You need $%d for this refill.", config.CashCost), refillType)
		return
	end
	if not DataManager:RefillWater(player) then
		if refillType ~= "Customer" and config.CashCost > 0 then DataManager:AddCash(player, config.CashCost) end
		respond(player, false, "The refill could not be completed.", refillType)
		return
	end
	local message = if refillType == "Customer"
		then string.format("Tank full! This job now pays %d%% less.", math.round(config.CustomerPayCut * 100))
		else string.format("Tank full! $%d paid.", config.CashCost)
	respond(player, true, message, refillType)
end

function WaterEconomyManager:Init()
	if initialized then return end
	initialized = true
	setupPrompts()
	WaterRefillRequest.OnServerEvent:Connect(function(player, refillType)
		if typeof(refillType) == "string" then handleRefill(player, refillType) end
	end)
	Players.PlayerRemoving:Connect(function(player) requestCooldown[player] = nil end)
	print("WaterEconomyManager: base, hydrant, and customer refill economy is ready.")
end

return WaterEconomyManager
