--!strict

-- Temporary base computer for local development. Replace this model with the
-- communal-base asset while preserving Workspace.Base.Computer.

local ShopTestFixture = {}
local initialized = false

function ShopTestFixture:Init()
	if initialized then
		return
	end
	initialized = true

	local base = workspace:FindFirstChild("Base")
	if base == nil then
		base = Instance.new("Folder")
		base.Name = "Base"
		base.Parent = workspace
	end
	if base:FindFirstChild("Computer") == nil then
		local computer = Instance.new("Model")
		computer.Name = "Computer"
		computer.Parent = base

		local monitor = Instance.new("Part")
		monitor.Name = "Monitor"
		monitor.Anchored = true
		monitor.Size = Vector3.new(3, 2.2, 0.4)
		monitor.Position = Vector3.new(0, 2.2, 8)
		monitor.Color = Color3.fromRGB(48, 88, 114)
		monitor.Material = Enum.Material.Metal
		monitor.Parent = computer
		computer.PrimaryPart = monitor
	end

	if base:FindFirstChild("EggIncubator") == nil then
		local incubator = Instance.new("Model")
		incubator.Name = "EggIncubator"
		incubator.Parent = base

		local eggPedestal = Instance.new("Part")
		eggPedestal.Name = "Pedestal"
		eggPedestal.Anchored = true
		eggPedestal.Shape = Enum.PartType.Ball
		eggPedestal.Size = Vector3.new(2.5, 2.5, 2.5)
		eggPedestal.Position = Vector3.new(5, 1.5, 8)
		eggPedestal.Color = Color3.fromRGB(255, 210, 93)
		eggPedestal.Material = Enum.Material.Neon
		eggPedestal.Parent = incubator
		incubator.PrimaryPart = eggPedestal
	end
end

return ShopTestFixture
