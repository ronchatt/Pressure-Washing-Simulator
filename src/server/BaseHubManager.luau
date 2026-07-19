--!strict

-- Adds functional hub fixtures around the artist-authored Workspace.Base
-- without altering its imported meshes.

local Workspace = game:GetService("Workspace")

local BaseHubManager = {}
local initialized = false

local function ensurePart(parent: Instance, name: string): Part
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Part") then return existing end
	if existing then existing:Destroy() end
	local part = Instance.new("Part")
	part.Name = name
	part.Parent = parent
	return part
end

local function ensureInteriorLights(base: Instance, building: BasePart)
	local old = base:FindFirstChild("InteriorLights")
	if old and not old:IsA("Folder") then old:Destroy(); old = nil end
	local folder = old :: Folder?
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "InteriorLights"
		folder.Parent = base
	end
	local offsets = {
		Vector3.new(-0.25, 0, -0.25), Vector3.new(0.25, 0, -0.25),
		Vector3.new(-0.25, 0, 0.25), Vector3.new(0.25, 0, 0.25),
	}
	for index, fraction in offsets do
		local fixture = ensurePart(folder, string.format("CeilingLight%02d", index))
		fixture.Size = Vector3.new(2.8, 0.18, 2.8)
		fixture.Position = Vector3.new(
			building.Position.X + building.Size.X * fraction.X,
			building.Position.Y + building.Size.Y * 0.5 - 2.1,
			building.Position.Z + building.Size.Z * fraction.Z
		)
		fixture.Anchored = true
		fixture.CanCollide = false
		fixture.CanQuery = false
		fixture.CanTouch = false
		fixture.Material = Enum.Material.Neon
		fixture.Color = Color3.fromRGB(255, 236, 194)
		fixture.Transparency = 0.08
		local light = fixture:FindFirstChild("InteriorPointLight")
		if light and not light:IsA("PointLight") then light:Destroy(); light = nil end
		if light == nil then
			light = Instance.new("PointLight")
			light.Name = "InteriorPointLight"
			light.Parent = fixture
		end
		local typedLight = light :: PointLight
		typedLight.Color = Color3.fromRGB(255, 225, 178)
		typedLight.Brightness = 1.65
		typedLight.Range = 21
		typedLight.Shadows = false
	end
end

local function ensureStation(base: Instance, building: BasePart)
	local old = base:FindFirstChild("TruckSpawnStation")
	if old and not old:IsA("Model") then old:Destroy(); old = nil end
	local station = old :: Model?
	if station == nil then
		station = Instance.new("Model")
		station.Name = "TruckSpawnStation"
		station.Parent = base
	end
	station:SetAttribute("TruckSpawnStation", true)
	local center = Vector3.new(building.Position.X, 0.4, building.Position.Z)
	local platformPosition = Vector3.new(
		building.Position.X + building.Size.X * 0.5 - 5.5,
		0.3,
		building.Position.Z
	)
	local platform = ensurePart(station, "Platform")
	platform.Size = Vector3.new(5.5, 0.6, 4.2)
	platform.CFrame = CFrame.lookAt(platformPosition, Vector3.new(center.X, platformPosition.Y, center.Z))
	platform.Anchored = true
	platform.CanCollide = true
	platform.Material = Enum.Material.Metal
	platform.Color = Color3.fromRGB(28, 49, 65)
	local terminal = ensurePart(station, "SpawnTerminal")
	terminal.Size = Vector3.new(1.7, 3.1, 1.25)
	terminal.CFrame = platform.CFrame * CFrame.new(0, 1.85, 0.85)
	terminal.Anchored = true
	terminal.CanCollide = true
	terminal.Material = Enum.Material.Metal
	terminal.Color = Color3.fromRGB(34, 143, 199)
	terminal:SetAttribute("TruckSpawnTerminal", true)
	local prompt = terminal:FindFirstChild("SpawnTruckPrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then prompt:Destroy(); prompt = nil end
	if prompt == nil then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SpawnTruckPrompt"
		prompt.Parent = terminal
	end
	local typedPrompt = prompt :: ProximityPrompt
	typedPrompt.ActionText = "Spawn Truck"
	typedPrompt.ObjectText = "Vehicle Dispatch"
	typedPrompt.KeyboardKeyCode = Enum.KeyCode.E
	typedPrompt.HoldDuration = 0.65
	typedPrompt.MaxActivationDistance = 11
	typedPrompt.RequiresLineOfSight = false
	local billboard = terminal:FindFirstChild("StationSign")
	if billboard then billboard:Destroy() end
	local sign = Instance.new("BillboardGui")
	sign.Name = "StationSign"
	sign.Size = UDim2.fromOffset(210, 54)
	sign.StudsOffset = Vector3.new(0, 2.6, 0)
	sign.AlwaysOnTop = false
	sign.Parent = terminal
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(10, 25, 36)
	text.BackgroundTransparency = 0.12
	text.BorderSizePixel = 0
	text.Font = Enum.Font.GothamBold
	text.Text = "SPAWN TRUCK"
	text.TextColor3 = Color3.fromRGB(92, 210, 255)
	text.TextSize = 20
	text.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = text
end

function BaseHubManager:Init()
	if initialized then return end
	initialized = true
	local base = Workspace:FindFirstChild("Base")
	local building = base and base:FindFirstChild("Building", true)
	local computer = base and base:FindFirstChild("Computer", true)
	if base == nil or not building or not building:IsA("BasePart") or not computer or not computer:IsA("BasePart") then
		warn("BaseHubManager requires Workspace.Base.Building and Workspace.Base.Computer")
		return
	end
	ensureInteriorLights(base, building)
	ensureStation(base, building)
	print("BaseHubManager: interior lighting and truck spawn station are ready.")
end

return BaseHubManager
