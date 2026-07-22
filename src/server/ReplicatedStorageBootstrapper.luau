--!strict

-- Runs before every gameplay module is required. This guarantees that shared
-- runtime containers and RemoteEvents exist even when Studio has not yet
-- received the corresponding instances from a Rojo project sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_EVENT_NAMES = {
	"CleanSegmentRequest",
	"CleanSegmentResult",
	"SprayWaterRequest",
	"AcceptJobRequest",
	"QuitJobRequest",
	"JobStateChanged",
	"JobStateRequest",
	"TutorialStateRequest",
	"TutorialStateChanged",
	"TutorialCompleteRequest",
	"PurchaseItemRequest",
	"EquipItemRequest",
	"PurchaseTankRequest",
	"ShopStateRequest",
	"ShopStateChanged",
	"WaterRefillRequest",
	"WaterRefillResult",
	"HatchEggRequest",
	"PetHatched",
	"EquipPetRequest",
	"PetInventoryChanged",
	"PetInventoryRequest",
	"SprintStateRequest",
	"RespawnVehicleRequest",
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

	local remotes = ensureFolder(ReplicatedStorage, "Remotes")
	for _, remoteName in REMOTE_EVENT_NAMES do
		ensureRemoteEvent(remotes, remoteName)
	end

	ensureFolder(ReplicatedStorage, "Washers")
	ensureFolder(ReplicatedStorage, "Vehicles")
	ensureFolder(ReplicatedStorage, "Pets")
end

return ReplicatedStorageBootstrapper
