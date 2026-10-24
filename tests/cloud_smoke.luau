-- Placeholder cloud smoke for the new skeleton: proves Open Cloud can load
-- the place and execute code against it. Returns a version handshake.

local Config = require(game:GetService("ReplicatedStorage").Shared.config)
print("cloud smoke handshake, version " .. Config.Version)
return { ok = true, version = Config.Version }
