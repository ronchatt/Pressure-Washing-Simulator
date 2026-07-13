--!strict

-- Temporary server-replicated test content. It makes the security path
-- testable now; replace it with production washer assets and authored jobs.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DIRT_TAG = "DirtSegment"
local GRID_NAME = "LocalDirtGridTest"
local WASHER_NAME = "Basic Backpack"

local WasherTestFixture = {}
local initialized = false

local function createWasher(player: Player)
	local backpack = player:WaitForChild("Backpack")
	if backpack:FindFirstChild(WASHER_NAME) ~= nil or (player.Character and player.Character:FindFirstChild(WASHER_NAME) ~= nil) then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = WASHER_NAME
	tool.ToolTip = "Development pressure washer"
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 0.45, 2.2)
	handle.Color = Color3.fromRGB(50, 65, 80)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	tool.Parent = backpack
end

local function watchPlayer(player: Player)
	-- Backpack and character creation can finish after PlayerAdded. Deferring
	-- this guarantees the temporary server tool exists in a fresh playtest.
	task.defer(createWasher, player)
	player.CharacterAdded:Connect(function()
		task.defer(createWasher, player)
	end)
end

local function createGrid()
	if workspace:FindFirstChild(GRID_NAME) ~= nil then
		return
	end

	local gridFolder = Instance.new("Folder")
	gridFolder.Name = GRID_NAME
	gridFolder.Parent = workspace

	local segmentSize = Vector3.new(4, 4, 0.3)
	local gridOrigin = Vector3.new(0, 10, -32)

	for row = 0, 4 do
		for column = 0, 4 do
			local segment = Instance.new("Part")
			segment.Name = string.format("Dirt_%d_%d", row + 1, column + 1)
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanQuery = true
			segment.CastShadow = false
			segment.Material = Enum.Material.Ground
			segment.Color = Color3.fromRGB(87, 57, 38)
			segment.Size = segmentSize
			segment.Position = gridOrigin + Vector3.new((column - 2) * segmentSize.X, (row - 2) * segmentSize.Y, 0)
			segment:SetAttribute("JobID", "Bench_1")
			segment.Parent = gridFolder

			CollectionService:AddTag(segment, DIRT_TAG)
		end
	end
end

local function createJobSites()
	local jobSites = workspace:FindFirstChild("JobSites")
	if jobSites == nil then
		jobSites = Instance.new("Folder")
		jobSites.Name = "JobSites"
		jobSites.Parent = workspace
	end

	if jobSites:FindFirstChild("Bench_1") ~= nil then
		return
	end

	local site = Instance.new("Model")
	site.Name = "Bench_1"
	site.Parent = jobSites

	local anchor = Instance.new("Part")
	anchor.Name = "WaypointAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = Vector3.new(0, 1, -32)
	anchor.Parent = site
	site.PrimaryPart = anchor
end

function WasherTestFixture:Init()
	if initialized then
		return
	end
	initialized = true

	createJobSites()
	createGrid()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return WasherTestFixture
