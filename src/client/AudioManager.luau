--!strict

-- Central client audio mixer. Gameplay controllers call the small public API;
-- server-authoritative RemoteEvents drive rewards, refills, jobs, and hatches.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local AudioManager = {}
local initialized = false
local lastImpactAt = 0
local impactIndex = 0
local boundButtons = setmetatable({} :: {[GuiButton]: boolean}, { __mode = "k" })

local SOUND_IDS: {[string]: string} = {
	UIClick = "rbxassetid://88442833509532",
	WaterImpact1 = "rbxassetid://9125703162",
	WaterImpact2 = "rbxassetid://9125702439",
	WaterImpact3 = "rbxassetid://9125702803",
	Refill = "rbxassetid://9120502198",
	JobComplete = "rbxassetid://1839881844",
	Cash = "rbxassetid://109376364304066",
	HatchCrack = "rbxassetid://9120967605",
	Ambience = "rbxassetid://9117064941",
}

local sfxGroup = SoundService:FindFirstChild("SimulatorSFX") :: SoundGroup?
if sfxGroup == nil then
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SimulatorSFX"
	sfxGroup.Parent = SoundService
end

local ambienceGroup = SoundService:FindFirstChild("SimulatorAmbience") :: SoundGroup?
if ambienceGroup == nil then
	ambienceGroup = Instance.new("SoundGroup")
	ambienceGroup.Name = "SimulatorAmbience"
	ambienceGroup.Parent = SoundService
end

local function updateMixerVolumes()
	local sfx = player:GetAttribute("SFXVolume")
	local music = player:GetAttribute("MusicVolume")
	local sfxMixer = sfxGroup :: SoundGroup
	local ambienceMixer = ambienceGroup :: SoundGroup
	sfxMixer.Volume = if typeof(sfx) == "number" then math.clamp(sfx, 0, 1) else 0.5
	ambienceMixer.Volume = if typeof(music) == "number" then math.clamp(music, 0, 1) else 0.5
end

local function createSound(name: string, soundID: string, group: SoundGroup): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundID
	sound.SoundGroup = group
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = 65
	return sound
end

function AudioManager:Play(name: string, volume: number?, playbackSpeed: number?)
	local soundID = SOUND_IDS[name]
	if soundID == nil then return end
	local sound = createSound(name, soundID, sfxGroup :: SoundGroup)
	sound.Volume = volume or 0.35
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 12)
end

function AudioManager:PlayAt(name: string, parent: Instance, volume: number?, playbackSpeed: number?)
	local soundID = SOUND_IDS[name]
	if soundID == nil then return end
	local sound = createSound(name, soundID, sfxGroup :: SoundGroup)
	sound.Volume = volume or 0.18
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function getSurfacePitch(material: Enum.Material): number
	if material == Enum.Material.Metal
		or material == Enum.Material.DiamondPlate
		or material == Enum.Material.CorrodedMetal
	then
		return 1.16
	elseif material == Enum.Material.Wood or material == Enum.Material.WoodPlanks then
		return 0.9
	elseif material == Enum.Material.Glass or material == Enum.Material.Ice then
		return 1.25
	elseif material == Enum.Material.Grass
		or material == Enum.Material.Ground
		or material == Enum.Material.Mud
		or material == Enum.Material.Fabric
	then
		return 0.82
	end
	return 1
end

function AudioManager:UpdateSprayImpact(hitPart: BasePart?, pressure: number, washingDirt: boolean)
	if hitPart == nil or pressure <= 0 then return end
	local now = os.clock()
	local interval = if washingDirt then 0.2 else 0.3
	if now - lastImpactAt < interval then return end
	lastImpactAt = now
	impactIndex = impactIndex % 3 + 1
	local pitchJitter = 0.96 + math.random() * 0.08
	local pitch = getSurfacePitch(hitPart.Material) * pitchJitter
	local volume = (if washingDirt then 0.105 else 0.055) * math.clamp(pressure, 0.25, 1)
	self:PlayAt("WaterImpact" .. tostring(impactIndex), hitPart, volume, pitch)
end

local function bindButton(button: GuiButton)
	if boundButtons[button] then return end
	boundButtons[button] = true
	button.Activated:Connect(function()
		AudioManager:Play("UIClick", 0.16, 1 + (math.random() - 0.5) * 0.04)
	end)
end

local function bindPlayerGuiButtons()
	local playerGui = player:WaitForChild("PlayerGui")
	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("GuiButton") then bindButton(descendant) end
	end
	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then bindButton(descendant) end
	end)
end

local function startAmbience()
	local existing = SoundService:FindFirstChild("NeighborhoodAmbience")
	if existing and existing:IsA("Sound") then existing:Destroy() end
	local ambience = createSound("NeighborhoodAmbience", SOUND_IDS.Ambience, ambienceGroup :: SoundGroup)
	ambience.Looped = true
	ambience.Volume = 0.2
	ambience.Parent = SoundService
	ambience:Play()
end

local function connectGameplayFeedback()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent
	local WaterRefillResult = remotes:WaitForChild("WaterRefillResult") :: RemoteEvent
	local PetHatched = remotes:WaitForChild("PetHatched") :: RemoteEvent
	local ShopStateChanged = remotes:WaitForChild("ShopStateChanged") :: RemoteEvent

	JobStateChanged.OnClientEvent:Connect(function(state)
		if typeof(state) ~= "table" then return end
		if state.State == "Active" then
			AudioManager:Play("UIClick", 0.28, 1.2)
		elseif state.State == "Completed" then
			AudioManager:Play("JobComplete", 0.48, 1)
			task.delay(0.35, function() AudioManager:Play("Cash", 0.34, 1.05) end)
		elseif state.State == "Rejected" or state.State == "Quit" then
			AudioManager:Play("UIClick", 0.25, 0.58)
		end
	end)

	WaterRefillResult.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" then return end
		if result.Success == true then
			AudioManager:Play("Refill", 0.38, 1.06)
		else
			AudioManager:Play("UIClick", 0.25, 0.58)
		end
	end)

	PetHatched.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" or result.Success ~= true then return end
		AudioManager:Play("HatchCrack", 0.32, 1.18)
		task.delay(0.28, function() AudioManager:Play("JobComplete", 0.3, 1.22) end)
	end)

	ShopStateChanged.OnClientEvent:Connect(function(state)
		if typeof(state) ~= "table" or typeof(state.Notice) ~= "string" then return end
		if state.Success == true then
			local notice = string.lower(state.Notice)
			if string.find(notice, "purchased", 1, true) or string.find(notice, "upgraded", 1, true) then
				AudioManager:Play("Cash", 0.3, 1.12)
			else
				AudioManager:Play("UIClick", 0.28, 1.3)
			end
		else
			AudioManager:Play("UIClick", 0.24, 0.58)
		end
	end)

	local initialWater = player:GetAttribute("Water")
	local previousWater = if typeof(initialWater) == "number" then initialWater else nil
	player:GetAttributeChangedSignal("Water"):Connect(function()
		local water = player:GetAttribute("Water")
		if typeof(water) ~= "number" then return end
		if previousWater ~= nil and previousWater > 0 and water <= 0 then
			AudioManager:Play("UIClick", 0.36, 0.45)
		end
		previousWater = water
	end)

	ProximityPromptService.PromptTriggered:Connect(function()
		AudioManager:Play("UIClick", 0.14, 0.9)
	end)
end

function AudioManager:Init()
	if initialized then return end
	initialized = true
	updateMixerVolumes()
	player:GetAttributeChangedSignal("SFXVolume"):Connect(updateMixerVolumes)
	player:GetAttributeChangedSignal("MusicVolume"):Connect(updateMixerVolumes)
	bindPlayerGuiButtons()
	startAmbience()
	connectGameplayFeedback()
end

return AudioManager
