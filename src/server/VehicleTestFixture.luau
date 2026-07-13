--!strict

-- Temporary server fixtures for testing the vehicle systems in this otherwise
-- empty project. Replace these with authored models under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleTestFixture = {}
local initialized = false

local function weld(part0: BasePart, part1: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = part0
	constraint.Part1 = part1
	constraint.Parent = part0
end

local function createPickupTemplate(vehicles: Folder)
	if vehicles:FindFirstChild("Basic Pickup") ~= nil then
		return
	end

	local truck = Instance.new("Model")
	truck.Name = "Basic Pickup"
	truck.Parent = vehicles

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(6, 1.5, 10)
	body.Color = Color3.fromRGB(48, 92, 160)
	body.Material = Enum.Material.Metal
	body.Parent = truck
	truck.PrimaryPart = body

	local seat = Instance.new("VehicleSeat")
	seat.Name = "VehicleSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = body.CFrame * CFrame.new(0, 1.25, 0.8)
	seat.Color = Color3.fromRGB(35, 38, 45)
	seat.Parent = truck
	weld(body, seat)

	for _, offset in ipairs({ Vector3.new(-2.8, -1.1, -3.2), Vector3.new(2.8, -1.1, -3.2), Vector3.new(-2.8, -1.1, 3.2), Vector3.new(2.8, -1.1, 3.2) }) do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(1.6, 1.6, 1)
		wheel.CFrame = body.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
		wheel.Color = Color3.fromRGB(25, 25, 28)
		wheel.Material = Enum.Material.Rubber
		wheel.Parent = truck
		weld(body, wheel)
	end
end

local function createParking()
	if workspace:FindFirstChild("BaseParking") ~= nil then
		return
	end

	local parking = Instance.new("Folder")
	parking.Name = "BaseParking"
	parking.Parent = workspace

	for index = 1, 8 do
		local spot = Instance.new("Part")
		spot.Name = string.format("Spawn_%02d", index)
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanQuery = false
		spot.Transparency = 1
		spot.Size = Vector3.new(10, 1, 16)
		spot.CFrame = CFrame.new((index - 4.5) * 13, 0.5, 22)
		spot.Parent = parking
	end
end

function VehicleTestFixture:Init()
	if initialized then
		return
	end
	initialized = true

	local vehicles = ReplicatedStorage:FindFirstChild("Vehicles")
	if vehicles == nil then
		vehicles = Instance.new("Folder")
		vehicles.Name = "Vehicles"
		vehicles.Parent = ReplicatedStorage
	end

	createPickupTemplate(vehicles)
	createParking()
end

return VehicleTestFixture
