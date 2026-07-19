--!strict

print("DIAGNOSTIC: EquipmentManager script is RUNNING.")

-- Server-owned washer lifecycle. Profile data chooses the template; clients
-- only receive the resulting Tool and cannot request arbitrary equipment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local SharedShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedShopData"))
local washersInstance = ReplicatedStorage:WaitForChild("Washers")
assert(washersInstance:IsA("Folder"), "ReplicatedStorage.Washers must be a Folder")
local Washers = washersInstance :: Folder

local EquipmentManager = {}
local initialized = false
local equippingPlayers: {[Player]: boolean} = {}
local BACKPACK_SOURCE_NAME = "Powerwashing Backpack"
local WAND_SOURCE_NAME = "Powerwashing Wand"
local BACKPACK_TEMPLATE_NAME = "Basic Backpack Accessory"
local WORN_BACKPACK_ATTRIBUTE = "PressureWasherBackpack"
local EQUIPMENT_ID_ATTRIBUTE = "PressureWasherEquipmentId"

local function configurePart(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function configureHandle(tool: Tool): BasePart
	local existing = tool:FindFirstChild("Handle")
	if existing and existing:IsA("BasePart") then
		configurePart(existing)
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 0.45, 2.2)
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.Color = Color3.fromRGB(50, 65, 80)
	handle.Material = Enum.Material.Metal
	handle.Parent = tool
	return handle
end

local function findImportedEquipment(): (Accessory?, Tool?)
	local backpack = workspace:FindFirstChild(BACKPACK_SOURCE_NAME, true)
	local wand = workspace:FindFirstChild(WAND_SOURCE_NAME, true)
	return if backpack and backpack:IsA("Accessory") then backpack else nil,
		if wand and wand:IsA("Tool") then wand else nil
end

local function createImportedBackpackTemplate(backpackSource: Accessory): Accessory
	local backpackTemplate = backpackSource:Clone()
	backpackTemplate.Name = BACKPACK_TEMPLATE_NAME
	backpackTemplate:SetAttribute(WORN_BACKPACK_ATTRIBUTE, true)
	local backpackHandle = backpackTemplate:FindFirstChild("Handle")
	if backpackHandle and backpackHandle:IsA("BasePart") then
		configurePart(backpackHandle)
		local bodyBackAttachment = backpackHandle:FindFirstChild("BodyBackAttachment")
		if bodyBackAttachment and bodyBackAttachment:IsA("Attachment") then
			-- The Blender attachment was at the mesh center. Offset it toward the
			-- character so the tank itself rests visibly behind the torso.
			bodyBackAttachment.Position = Vector3.new(0, -0.08, -0.42)
		end
	end
	return backpackTemplate
end

local function createImportedBasicWasher(wandSource: Tool): Tool
	local tool = wandSource:Clone()
	tool.Name = "Basic Backpack"
	tool.ToolTip = "Basic pressure washer"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("IsPressureWasher", true)
	tool:SetAttribute("UsesImportedEquipment", true)
	-- Move the mesh forward so the rear grip of the imported wand, rather than
	-- its center, sits in the character's hand.
	tool.Grip = wandSource.Grip * CFrame.new(0, 0, 1.05)

	local handle = configureHandle(tool)
	local existingOrigin = handle:FindFirstChild("SprayOrigin")
	if existingOrigin then
		existingOrigin:Destroy()
	end
	local sprayOrigin = Instance.new("Attachment")
	sprayOrigin.Name = "SprayOrigin"
	-- The imported wand's long axis is local Z. Its forward/nozzle end is -Z.
	sprayOrigin.Position = Vector3.new(0, 0, -handle.Size.Z * 0.5)
	sprayOrigin.Parent = handle

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("RopeConstraint") then
			-- A real rope can yank an un-welded accessory across the map during
			-- its first physics frame. A visual Beam is connected after equipping.
			descendant.Enabled = false
			descendant.Visible = false
			descendant.Attachment1 = nil
		end
	end
	return tool
end

local function ensureBasicWasher(): Tool
	local existing = Washers:FindFirstChild("Basic Backpack")
	local backpackSource, wandSource = findImportedEquipment()
	if backpackSource and wandSource then
		local storedBackpackTemplate = Washers:FindFirstChild(BACKPACK_TEMPLATE_NAME)
		if existing and existing:IsA("Tool")
			and existing:GetAttribute("UsesImportedEquipment") == true
			and storedBackpackTemplate and storedBackpackTemplate:IsA("Accessory")
			and storedBackpackTemplate:FindFirstChild("Handle") ~= nil
		then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		if storedBackpackTemplate then
			storedBackpackTemplate:Destroy()
		end
		local backpackTemplate = createImportedBackpackTemplate(backpackSource)
		backpackTemplate.Parent = Washers
		local importedTool = createImportedBasicWasher(wandSource)
		importedTool.Parent = Washers
		return importedTool
	end

	if existing and existing:IsA("Tool") then
		existing:SetAttribute("IsPressureWasher", true)
		configureHandle(existing)
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local tool = Instance.new("Tool")
	tool.Name = "Basic Backpack"
	tool.ToolTip = "Basic pressure washer"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("IsPressureWasher", true)
	configureHandle(tool)
	tool.Parent = Washers
	return tool
end

local function applyPlaceholderAppearance(tool: Tool, washerData)
	tool.ToolTip = string.format(
		"Tier %d | %.1fx power | %.1fx width",
		washerData.Tier,
		washerData.CleanSpeed / 0.5,
		washerData.SprayWidth
	)
	tool:SetAttribute("IsPressureWasher", true)
	tool:SetAttribute("WasherTier", washerData.Tier)
	tool:SetAttribute("WasherAccentColor", washerData.AccentColor)
	tool:SetAttribute("PlaceholderWasher", washerData.Tier > 1)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = washerData.AccentColor
			if washerData.Tier > 1 then
				descendant.Material = Enum.Material.Metal
			end
		end
	end
end

local function ensureWasherTemplates()
	local basic = ensureBasicWasher()
	local basicData = SharedShopData.Washers["Basic Backpack"]
	if basicData then
		basic:SetAttribute("WasherTier", basicData.Tier)
		basic:SetAttribute("WasherAccentColor", basicData.AccentColor)
	end

	for _, washerName in SharedShopData.WasherOrder do
		if washerName == basic.Name then
			continue
		end
		local washerData = SharedShopData.Washers[washerName]
		if washerData == nil then
			continue
		end
		local existing = Washers:FindFirstChild(washerName)
		if existing then
			existing:Destroy()
		end
		local placeholder = basic:Clone()
		placeholder.Name = washerName
		applyPlaceholderAppearance(placeholder, washerData)
		placeholder.Parent = Washers
	end
end

local function removeWornBackpack(character: Model, equipmentID: string?)
	for _, child in character:GetChildren() do
		local childEquipmentID = child:GetAttribute(EQUIPMENT_ID_ATTRIBUTE)
		if child:IsA("Accessory")
			and child:GetAttribute(WORN_BACKPACK_ATTRIBUTE) == true
			and (equipmentID == nil or childEquipmentID == equipmentID)
		then
			child:Destroy()
		end
	end
end

local function connectImportedEquipment(player: Player, tool: Tool)
	-- Accessories cannot be used as reusable templates beneath a Tool: Roblox
	-- may strip their Handles while the Tool moves between Backpack/Character.
	-- Keep the immutable template in ReplicatedStorage instead.
	local backpackTemplate = Washers:FindFirstChild(BACKPACK_TEMPLATE_NAME)
	if backpackTemplate == nil or not backpackTemplate:IsA("Accessory") then
		return
	end

	local storedEquipmentID = tool:GetAttribute(EQUIPMENT_ID_ATTRIBUTE)
	local equipmentID: string
	if typeof(storedEquipmentID) == "string" then
		equipmentID = storedEquipmentID
	else
		equipmentID = HttpService:GenerateGUID(false)
		tool:SetAttribute(EQUIPMENT_ID_ATTRIBUTE, equipmentID)
	end
	local wornBackpack: Accessory? = nil
	local hoseBeam: Beam? = nil
	local lifecycleRevision = 0

	local function cleanOwnedVisuals()
		if hoseBeam then
			hoseBeam:Destroy()
			hoseBeam = nil
		end
		if wornBackpack then
			wornBackpack:Destroy()
			wornBackpack = nil
		elseif player.Character then
			removeWornBackpack(player.Character, equipmentID)
		end
	end

	tool.Equipped:Connect(function()
		lifecycleRevision += 1
		local equippedRevision = lifecycleRevision
		-- Let Roblox finish reparenting the Tool before creating character-bound
		-- visuals. A stale Unequipped event from a rapid hotbar switch then loses
		-- its revision and cannot delete this new backpack.
		task.defer(function()
			if equippedRevision ~= lifecycleRevision then
				return
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if character == nil or humanoid == nil or tool.Parent ~= character then
				return
			end
			cleanOwnedVisuals()

			local accessory = backpackTemplate:Clone()
			accessory.Name = BACKPACK_SOURCE_NAME
			accessory:SetAttribute(WORN_BACKPACK_ATTRIBUTE, true)
			accessory:SetAttribute(EQUIPMENT_ID_ATTRIBUTE, equipmentID)
			local accessoryHandle = accessory:FindFirstChild("Handle")
			if accessoryHandle and accessoryHandle:IsA("BasePart") then
				configurePart(accessoryHandle)
			end
			local accentColor = tool:GetAttribute("WasherAccentColor")
			if typeof(accentColor) == "Color3" and tool:GetAttribute("PlaceholderWasher") == true then
				for _, descendant in accessory:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Color = accentColor
					end
				end
			end
			humanoid:AddAccessory(accessory)
			wornBackpack = accessory

			local wandHandle = tool:FindFirstChild("Handle")
			local hoseOutput = accessory:FindFirstChild("Hose Output", true)
			local hoseInput = wandHandle and wandHandle:FindFirstChild("Hose Input", true)
			if hoseInput and hoseInput:IsA("Attachment") and hoseOutput and hoseOutput:IsA("Attachment") then
				local visualHose = Instance.new("Beam")
				visualHose.Name = "PressureWasherHose"
				visualHose.Attachment0 = hoseInput
				visualHose.Attachment1 = hoseOutput
				visualHose.FaceCamera = true
				visualHose.Segments = 12
				visualHose.CurveSize0 = 0.45
				visualHose.CurveSize1 = -0.45
				visualHose.Width0 = 0.055
				visualHose.Width1 = 0.055
				visualHose.Color = ColorSequence.new(Color3.fromRGB(32, 37, 42))
				visualHose.Transparency = NumberSequence.new(0.08)
				visualHose.Parent = wandHandle
				hoseBeam = visualHose
			end
		end)
	end)

	tool.Unequipped:Connect(function()
		lifecycleRevision += 1
		local unequippedRevision = lifecycleRevision
		task.defer(function()
			if unequippedRevision ~= lifecycleRevision then
				return
			end
			if player.Character and tool.Parent == player.Character then
				return
			end
			cleanOwnedVisuals()
		end)
	end)

	tool.Destroying:Connect(function()
		lifecycleRevision += 1
		cleanOwnedVisuals()
	end)
end

local function removeCurrentWashers(player: Player)
	local function cleanContainer(container: Instance?)
		if container == nil then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and (child:GetAttribute("IsPressureWasher") == true or Washers:FindFirstChild(child.Name) ~= nil) then
				child:Destroy()
			end
		end
	end

	cleanContainer(player:FindFirstChild("Backpack"))
	cleanContainer(player.Character)
end

function EquipmentManager:EquipPlayer(player: Player): Tool?
	if equippingPlayers[player] then
		return nil
	end
	equippingPlayers[player] = true
	task.delay(5, function()
		equippingPlayers[player] = nil
	end)
	print("DIAGNOSTIC: Attempting to give tool to:", player.Name)

	local data = DataManager:GetData(player)
	if data == nil or player.Parent == nil then
		equippingPlayers[player] = nil
		return nil
	end

	local backpackInstance = player:WaitForChild("Backpack")
	if not backpackInstance:IsA("Backpack") or player.Parent == nil then
		equippingPlayers[player] = nil
		return nil
	end

	local basicWasher = ensureBasicWasher()
	local requestedTemplate = Washers:WaitForChild(data.EquippedWasher, 2)
	local template: Tool = basicWasher
	if requestedTemplate and requestedTemplate:IsA("Tool") and requestedTemplate:FindFirstChild("Handle") then
		template = requestedTemplate
	elseif data.EquippedWasher ~= basicWasher.Name then
		warn(string.format("Washer '%s' is unavailable; equipping Basic Backpack for %s", data.EquippedWasher, player.Name))
	end

	-- PlayerAdded/profile loading and CharacterAdded can finish on the same
	-- frame. Reuse the correct tool instead of replacing it and firing stale
	-- Unequipped/Destroying cleanup against the newly equipped backpack.
	for _, container in { backpackInstance, player.Character } do
		if container then
			local current = container:FindFirstChild(data.EquippedWasher)
			if current and current:IsA("Tool") and current:GetAttribute("IsPressureWasher") == true then
				equippingPlayers[player] = nil
				return current
			end
		end
	end

	removeCurrentWashers(player)
	local clone = template:Clone()
	clone:SetAttribute("IsPressureWasher", true)
	clone:SetAttribute(EQUIPMENT_ID_ATTRIBUTE, HttpService:GenerateGUID(false))
	configureHandle(clone)
	connectImportedEquipment(player, clone)
	clone.Parent = backpackInstance
	print("DIAGNOSTIC: Tool successfully added to backpack.")
	player:SetAttribute("EquippedWasher", clone.Name)
	equippingPlayers[player] = nil
	return clone
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			EquipmentManager:EquipPlayer(player)
		end)
	end)

	if player.Character then
		task.defer(function()
			EquipmentManager:EquipPlayer(player)
		end)
	end
end

function EquipmentManager:Init()
	if initialized then
		return
	end
	initialized = true

	ensureWasherTemplates()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return EquipmentManager
