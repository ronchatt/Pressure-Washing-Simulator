--!strict

-- Runs before every gameplay module is required. This guarantees that shared
-- runtime containers and RemoteEvents exist even when Studio has not yet
-- received the corresponding instances from a Rojo project sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BLOCKED_SOUND_ASSET_ID = "188608071"

local function disableBlockedSound(instance: Instance)
	if not instance:IsA("Sound") or not string.find(instance.SoundId, BLOCKED_SOUND_ASSET_ID, 1, true) then
		return
	end
	local fullName = instance:GetFullName()
	local success, message = pcall(function()
		instance:Stop()
		instance.SoundId = ""
	end)
	if success then
		warn("DIAGNOSTIC: Cleared blocked sound from " .. fullName)
	else
		warn(string.format("DIAGNOSTIC: Could not clear blocked sound from %s: %s", fullName, tostring(message)))
	end
end

local REMOTE_EVENT_NAMES = {
	"CleanSegmentRequest",
	"SprayWaterRequest",
	"AcceptJobRequest",
	"QuitJobRequest",
	"JobStateChanged",
	"PurchaseItemRequest",
	"EquipItemRequest",
	"PurchaseTankRequest",
	"HatchEggRequest",
	"PetHatched",
	"EquipPetRequest",
	"PetInventoryChanged",
	"PetInventoryRequest",
}

local ReplicatedStorageBootstrapper = {}
local initialized = false

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		warn(string.format("Replacing %s.%s because it is not a Folder", parent:GetFullName(), name))
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteEvent(remotes: Folder, name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		warn(string.format("Replacing ReplicatedStorage.Remotes.%s because it is not a RemoteEvent", name))
		existing:Destroy()
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = name
	remoteEvent.Parent = remotes
	return remoteEvent
end

function ReplicatedStorageBootstrapper:Init()
	if initialized then
		return
	end
	initialized = true

	for _, descendant in game:GetDescendants() do
		disableBlockedSound(descendant)
	end
	game.DescendantAdded:Connect(disableBlockedSound)

	local remotes = ensureFolder(ReplicatedStorage, "Remotes")
	for _, remoteName in REMOTE_EVENT_NAMES do
		ensureRemoteEvent(remotes, remoteName)
	end

	ensureFolder(ReplicatedStorage, "Washers")
end

return ReplicatedStorageBootstrapper
