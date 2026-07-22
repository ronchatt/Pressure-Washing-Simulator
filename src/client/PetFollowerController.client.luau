--!strict

-- Lightweight client-rendered companions for every player. Drop a Model or
-- BasePart named after a PetID into ReplicatedStorage.Pets to replace a
-- placeholder later without changing follower logic or saved data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SharedPetData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedPetData"))
local petTemplates = ReplicatedStorage:WaitForChild("Pets")
local followersFolder = Workspace:FindFirstChild("ClientPetFollowers")
if followersFolder then followersFolder:Destroy() end
followersFolder = Instance.new("Folder")
followersFolder.Name = "ClientPetFollowers"
followersFolder.Parent = Workspace

type FollowerState = { Model: Model, CurrentCFrame: CFrame }
local followers: {[Player]: FollowerState} = {}
local connections: {[Player]: RBXScriptConnection} = {}

local function prepareModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = true
		end
	end
	if model.PrimaryPart == nil then model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true) end
end

local function part(model: Model, name: string, size: Vector3, color: Color3, offset: CFrame, shape: Enum.PartType?): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Color = color
	item.Material = Enum.Material.SmoothPlastic
	item.Shape = shape or Enum.PartType.Block
	item.CFrame = offset
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.Parent = model
	return item
end

local function createPlaceholder(petID: string): Model
	local definition = SharedPetData.Pets[petID]
	local model = Instance.new("Model")
	model.Name = petID
	local scale = if petID == "Dragon" then 1.18 else 1
	local body = part(model, "Body", Vector3.new(1.6, 1.35, 2.05) * scale, definition.Color, CFrame.new(), Enum.PartType.Ball)
	model.PrimaryPart = body
	part(model, "Head", Vector3.new(1.35, 1.25, 1.3) * scale, definition.Color:Lerp(Color3.new(1, 1, 1), 0.08), CFrame.new(Vector3.new(0, 0.45, -1.25) * scale), Enum.PartType.Ball)
	part(model, "LeftEar", Vector3.new(0.38, 0.7, 0.38) * scale, definition.Color, CFrame.new(Vector3.new(-0.42, 1.05, -1.35) * scale))
	part(model, "RightEar", Vector3.new(0.38, 0.7, 0.38) * scale, definition.Color, CFrame.new(Vector3.new(0.42, 1.05, -1.35) * scale))
	part(model, "Tail", Vector3.new(0.35, 0.35, 1.15) * scale, definition.RarityColor, CFrame.new(Vector3.new(0, 0.35, 1.35) * scale) * CFrame.Angles(math.rad(-28), 0, 0))
	local glow = Instance.new("PointLight")
	glow.Color = definition.RarityColor
	glow.Brightness = if petID == "Dragon" then 1.2 else 0.45
	glow.Range = if petID == "Dragon" then 8 else 4
	glow.Parent = body
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PetLabel"
	billboard.Size = UDim2.fromOffset(130, 30)
	billboard.StudsOffset = Vector3.new(0, 1.8 * scale, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = definition.Name .. "  •  " .. definition.Rarity
	label.TextColor3 = definition.RarityColor
	label.TextStrokeTransparency = 0.45
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.Parent = billboard
	return model
end

local function destroyFollower(targetPlayer: Player)
	local state = followers[targetPlayer]
	if state then state.Model:Destroy(); followers[targetPlayer] = nil end
end

local function refreshFollower(targetPlayer: Player)
	destroyFollower(targetPlayer)
	local petID = targetPlayer:GetAttribute("EquippedPetID")
	if typeof(petID) ~= "string" or SharedPetData.Pets[petID] == nil then return end
	local template = petTemplates:FindFirstChild(petID)
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	elseif template and template:IsA("BasePart") then
		model = Instance.new("Model")
		local clonedPart = template:Clone()
		clonedPart.Parent = model
		model.PrimaryPart = clonedPart
	else
		model = createPlaceholder(petID)
	end
	model.Name = string.format("%s_%d", petID, targetPlayer.UserId)
	prepareModel(model)
	model.Parent = followersFolder
	local root = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	local start = if root and root:IsA("BasePart") then root.CFrame * CFrame.new(2.8, -1.6, 3.2) else CFrame.new(0, -100, 0)
	model:PivotTo(start)
	followers[targetPlayer] = { Model = model, CurrentCFrame = start }
end

local function watchPlayer(targetPlayer: Player)
	if connections[targetPlayer] then connections[targetPlayer]:Disconnect() end
	connections[targetPlayer] = targetPlayer:GetAttributeChangedSignal("EquippedPetID"):Connect(function()
		refreshFollower(targetPlayer)
	end)
	targetPlayer.CharacterAdded:Connect(function() task.defer(function() refreshFollower(targetPlayer) end) end)
	refreshFollower(targetPlayer)
end

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(targetPlayer)
	destroyFollower(targetPlayer)
	if connections[targetPlayer] then connections[targetPlayer]:Disconnect(); connections[targetPlayer] = nil end
end)
for _, targetPlayer in Players:GetPlayers() do watchPlayer(targetPlayer) end

RunService.RenderStepped:Connect(function(deltaTime)
	local time = os.clock()
	for targetPlayer, state in followers do
		local root = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") or state.Model.Parent == nil then continue end
		local bob = math.sin(time * 3.2 + targetPlayer.UserId % 10) * 0.16
		local position = (root.CFrame * CFrame.new(2.8, -1.55 + bob, 3.2)).Position
		local lookTarget = Vector3.new(root.Position.X, position.Y, root.Position.Z)
		local desired = CFrame.lookAt(position, lookTarget)
		local alpha = 1 - math.exp(-8 * deltaTime)
		state.CurrentCFrame = state.CurrentCFrame:Lerp(desired, alpha)
		state.Model:PivotTo(state.CurrentCFrame)
	end
end)
