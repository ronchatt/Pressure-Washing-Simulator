--!strict

-- Client-only spray feedback and dirt visuals. Server validation, water use,
-- and job progress reporting are deliberately added in a later system.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PLAYER = Players.LocalPlayer
local WASHER_NAME = "Basic Backpack"
local DIRT_TAG = "DirtSegment"
local DEFAULT_CLEAN_SPEED = 0.5
local MAX_SPRAY_DISTANCE = 160

local mouse = PLAYER:GetMouse()
local CleanSegmentRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CleanSegmentRequest") :: RemoteEvent
local activeTool: Tool? = nil
local sprayEmitter: ParticleEmitter? = nil
local isSpraying = false
local connectedTools: {[Tool]: boolean} = {}

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

	local handle = tool:FindFirstChild("Handle")
	if handle ~= nil and handle:IsA("BasePart") then
		return handle
	end

	return nil
end

local function setSprayEnabled(enabled: boolean)
	isSpraying = enabled and activeTool ~= nil
	if sprayEmitter ~= nil then
		sprayEmitter.Enabled = isSpraying
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
	emitter.Rate = 180
	emitter.Lifetime = NumberRange.new(0.18, 0.3)
	emitter.Speed = NumberRange.new(70, 85)
	emitter.SpreadAngle = Vector2.new(2, 2)
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

local function findDirtSegment(hitInstance: Instance): Instance?
	if CollectionService:HasTag(hitInstance, DIRT_TAG) then
		return hitInstance
	end

	-- Decals do not receive raycast hits themselves. Supporting a tagged Decal
	-- under the hit part keeps the artist workflow flexible.
	for _, child in hitInstance:GetChildren() do
		if child:IsA("Decal") and CollectionService:HasTag(child, DIRT_TAG) then
			return child
		end
	end

	return nil
end

local function cleanSegment(segment: Instance, deltaTime: number)
	if segment:IsA("BasePart") then
		segment.Transparency = math.min(1, segment.Transparency + getCleanSpeed() * deltaTime)
		if segment.Transparency >= 1 then
			CollectionService:RemoveTag(segment, DIRT_TAG)
			segment.CanQuery = false
			CleanSegmentRequest:FireServer(segment)
			local progressSignal = PLAYER.PlayerGui:FindFirstChild("JobProgressPredicted")
			if progressSignal ~= nil and progressSignal:IsA("BindableEvent") then
				progressSignal:Fire(segment)
			end
		end
	elseif segment:IsA("Decal") then
		segment.Transparency = math.min(1, segment.Transparency + getCleanSpeed() * deltaTime)
		if segment.Transparency >= 1 then
			CollectionService:RemoveTag(segment, DIRT_TAG)
			CleanSegmentRequest:FireServer(segment)
			local progressSignal = PLAYER.PlayerGui:FindFirstChild("JobProgressPredicted")
			if progressSignal ~= nil and progressSignal:IsA("BindableEvent") then
				progressSignal:Fire(segment)
			end
		end
	end
end

local function connectTool(tool: Tool)
	if connectedTools[tool] or tool.Name ~= WASHER_NAME then
		return
	end
	connectedTools[tool] = true

	tool.Equipped:Connect(function()
		activeTool = tool
		sprayEmitter = ensureSprayEmitter(tool)
	end)

	tool.Unequipped:Connect(function()
		if activeTool == tool then
			setSprayEnabled(false)
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

local function watchContainer(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			connectTool(child)
		end
	end

	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			connectTool(child)
		end
	end)
end

watchContainer(PLAYER:WaitForChild("Backpack"))
PLAYER.CharacterAdded:Connect(watchContainer)
if PLAYER.Character ~= nil then
	watchContainer(PLAYER.Character)
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

RunService.Heartbeat:Connect(function(deltaTime)
	if not isSpraying or activeTool == nil then
		return
	end

	local nozzle = getNozzle(activeTool)
	local character = PLAYER.Character
	if nozzle == nil or character == nil then
		setSprayEnabled(false)
		return
	end

	local origin = nozzle.Position
	local target = mouse.Hit.Position
	local offset = target - origin
	if offset.Magnitude < 0.01 then
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, activeTool }
	raycastParams.IgnoreWater = true

	local result = workspace:Raycast(origin, offset.Unit * math.min(offset.Magnitude, MAX_SPRAY_DISTANCE), raycastParams)
	if result == nil then
		return
	end

	local segment = findDirtSegment(result.Instance)
	if segment ~= nil then
		cleanSegment(segment, deltaTime)
	end
end)
