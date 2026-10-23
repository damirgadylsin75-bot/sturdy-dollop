-- Remote plumbing: two RemoteEvents plus a server-side command router.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.config)

local Remotes = {}

local commandEvent, eventEvent
local handler = nil

function Remotes.init()
	local folder = Instance.new("Folder")
	folder.Name = Config.Net.RemotesFolder
	folder.Parent = ReplicatedStorage

	commandEvent = Instance.new("RemoteEvent")
	commandEvent.Name = Config.Net.Command
	commandEvent.Parent = folder

	eventEvent = Instance.new("RemoteEvent")
	eventEvent.Name = Config.Net.Event
	eventEvent.Parent = folder

	return folder
end

function Remotes.setHandler(fn)
	handler = fn
end

function Remotes.watch()
	commandEvent.OnServerEvent:Connect(function(player, cmd)
		if handler then
			local ok, err = pcall(handler, player, cmd)
			if not ok then
				warn("command error: " .. tostring(err))
			end
		end
	end)
end

function Remotes.send(payload)
	eventEvent:FireAllClients(payload)
end

function Remotes.sendTo(player, payload)
	eventEvent:FireClient(player, payload)
end

function Remotes.client()
	return commandEvent, eventEvent
end

return Remotes
