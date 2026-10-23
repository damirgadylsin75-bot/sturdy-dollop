// Headless round simulation: runs the actual game modules in real Luau (WASM)
// with the Roblox API stubbed out. Catches runtime/logic errors without Studio.
import fs from 'fs';
import path from 'path';
import * as luau from '@luau-rs/luau';

const repo = process.argv[2];
const scenarioPath = process.argv[3] || 'tests/sim_test.luau';
const noDefenses = process.argv.includes('--no-defenses');
const src = (p) => fs.readFileSync(path.join(repo, p), 'utf8');

const lua = await luau.Lua.create({});
lua.loadLibraries('all');

const BOOTSTRAP = `
local function lcgState(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return s
end
Random = {}
function Random.new(seed)
  local s = lcgState(seed or 42)
  local rng = {}
  function rng:NextNumber(a, b)
    s = (s * 16807) % 2147483647
    local v = s / 2147483647
    if a ~= nil and b ~= nil then return a + (b - a) * v end
    return v
  end
  function rng:NextInteger(a, b)
    s = (s * 16807) % 2147483647
    return a + (s % (b - a + 1))
  end
  return rng
end

local V2mt = {}
V2mt.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
V2mt.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
V2mt.__mul = function(a, b)
  if type(a) == "number" then return Vector2.new(a * b.X, a * b.Y) end
  if type(b) == "number" then return Vector2.new(a.X * b, a.Y * b) end
  error("bad Vector2 mul")
end
V2mt.__div = function(a, b)
  if type(b) == "number" then return Vector2.new(a.X / b, a.Y / b) end
  error("bad Vector2 div")
end
V2mt.__index = function(t, k)
  if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
  if k == "SquaredMagnitude" then return t.X * t.X + t.Y * t.Y end
  if k == "Unit" then
    local m = math.sqrt(t.X * t.X + t.Y * t.Y)
    if m < 1e-9 then return Vector2.new(0, 0) end
    return Vector2.new(t.X / m, t.Y / m)
  end
  if k == "Dot" then return function(s, o) return s.X * o.X + s.Y * o.Y end end
  if k == "Lerp" then return function(s, o, tt) return Vector2.new(s.X + (o.X - s.X) * tt, s.Y + (o.Y - s.Y) * tt) end end
  return nil
end
Vector2 = { new = function(x, y) return setmetatable({ X = x, Y = y }, V2mt) end }

local V3mt = {}
V3mt.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__mul = function(a, b)
  if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
  if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
  error("bad Vector3 mul")
end
V3mt.__index = function(t, k)
  if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
  if k == "Unit" then
    local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
    return Vector3.new(t.X / m, t.Y / m, t.Z / m)
  end
  if k == "Dot" then return function(s, o) return s.X * o.X + s.Y * o.Y + s.Z * o.Z end end
  return nil
end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V3mt) end }

local C3mt = {}
C3mt.__index = function(t, k)
  if k == "Lerp" then return function(s, o, tt) return s end end
  if k == "R" or k == "G" or k == "B" then return 0.2 end
  return nil
end
Color3 = {
  fromHex = function(h) return setmetatable({}, C3mt) end,
  new = function() return setmetatable({}, C3mt) end,
  fromRGB = function() return setmetatable({}, C3mt) end,
}

local function autoTable()
  return setmetatable({}, { __index = function(t, k) local v = autoTable() rawset(t, k, v) return v end })
end
Enum = autoTable()

local CFmt = { __mul = function(a, b) return a end }
local function cf() return setmetatable({}, CFmt) end
CFrame = {
  new = function() return cf() end,
  Angles = function() return cf() end,
  lookAt = function() return cf() end,
}

local function makeInstance(className)
  return setmetatable({ ClassName = className }, {
    __index = function(t, k)
      if k == "Destroy" then return function() end end
      return nil
    end,
    __newindex = function(t, k, v) rawset(t, k, v) end,
  })
end
Instance = { new = function(cn) return makeInstance(cn) end }

RaycastParams = { new = function() return makeInstance("RaycastParams") end }
workspace = { Raycast = function() return nil end }

NODES = {}
registry = {}
local function node(name)
  local n = { Name = name }
  NODES[name] = n
  return n
end
NODE_shared = node("Shared")
NODE_config = node("config")
NODE_mapgen = node("mapgen")
NODE_graph = node("graph")
NODE_server = node("server")
NODE_sim = node("sim")
NODE_scoring = node("scoring")
NODE_population = node("population")
NODE_units = node("units")
NODE_strikes = node("strikes")
NODE_config.Parent = NODE_shared
NODE_mapgen.Parent = NODE_shared
NODE_graph.Parent = NODE_shared
NODE_shared.config = NODE_config
NODE_shared.mapgen = NODE_mapgen
NODE_shared.graph = NODE_graph
NODE_sim.Parent = NODE_server
NODE_scoring.Parent = NODE_server
NODE_population.Parent = NODE_server
NODE_units.Parent = NODE_server
NODE_strikes.Parent = NODE_server
NODE_server.sim = NODE_sim
NODE_server.scoring = NODE_scoring
NODE_server.population = NODE_population
NODE_server.units = NODE_units
NODE_server.strikes = NODE_strikes
NODE_remotes = node("remotes")
NODE_city = node("city")
NODE_server.remotes = NODE_remotes
NODE_server.city = NODE_city
local RS = { Shared = NODE_shared }
services = { ReplicatedStorage = RS, TweenService = { Create = function() return { Play = function() end } end } }
game = { GetService = function(_, name) return services[name] end }
require = function(target)
  local mod = registry[target]
  if mod == nil then error("module not registered for this node", 2) end
  return mod
end
function warn(...) end

LOG = {}
function log(msg) LOG[#LOG + 1] = tostring(msg) end
`;
// deterministic math.random for reproducible runs
await lua.execute('math.randomseed(20261023)');
await lua.execute(BOOTSTRAP);

const nodeRows = await lua.execute('return NODE_server, NODE_config, NODE_mapgen, NODE_graph, NODE_sim, NODE_scoring, NODE_population, NODE_units, NODE_strikes, NODE_remotes, NODE_city');
const nodeByName = {};
for (const n of nodeRows) nodeByName[String(n.get('Name'))] = n;

function loadModule(nodeName, relPath) {
  const nodeTable = nodeByName[nodeName];
  lua.globals.set('script', nodeTable);
  const fn = lua.load(src(relPath), { name: '@' + relPath });
  const results = fn.call();
  lua.globals.set('__MOD', results[0] ?? null);
  lua.globals.set('__NODE', nodeTable);
  lua.execute('registry[__NODE] = __MOD');
}

loadModule('config', 'src/shared/config.luau');
loadModule('mapgen', 'src/shared/mapgen.luau');
loadModule('graph', 'src/shared/graph.luau');
loadModule('sim', 'src/server/sim.luau');
loadModule('scoring', 'src/server/scoring.luau');
loadModule('population', 'src/server/population.luau');
loadModule('units', 'src/server/units.luau');
loadModule('strikes', 'src/server/strikes.luau');
loadModule('remotes', 'src/server/remotes.luau');
loadModule('city', 'src/server/city.luau');
console.log('all modules loaded');

// ---------- boot mode: run the real init.server.luau ----------
const BOOT_EXTRA = `
-- richer stubs so the real init script can boot headless
local function newSignal()
	local sig = { handlers = {} }
	function sig:Connect(fn)
		self.handlers[#self.handlers + 1] = fn
		return { Disconnect = function() end }
	end
	function sig:Fire(...)
		for _, fn in ipairs(self.handlers) do fn(...) end
	end
	return sig
end
GENERIC_SIGNAL = newSignal()

ALL_INSTANCES = {}
local function newInstance(className)
	local inst = {
		ClassName = className,
		_children = {},
		_attrs = {},
	}
	ALL_INSTANCES[#ALL_INSTANCES + 1] = inst
	function inst:SetAttribute(n, v) self._attrs[n] = v end
	function inst:GetAttribute(n) return self._attrs[n] end
	function inst:GetAttributeChangedSignal() return GENERIC_SIGNAL end
	function inst:WaitForChild(n) return self._children[n] end
	function inst:FindFirstChild(n) return self._children[n] end
	function inst:Destroy() end
	function inst:IsA(c) return c == self.ClassName end
	function inst:FireAllClients() end
	function inst:FireServer() end
	function inst:FireClient() end
	return setmetatable(inst, {
		__index = function()
			return GENERIC_SIGNAL -- unknown members act like connectable events
		end,
		__newindex = function(t, k, v) rawset(t, k, v) end,
	})
end
Instance = { new = function(cn) return newInstance(cn) end }
RaycastParams = { new = function() return newInstance("RaycastParams") end }

task = {
	spawn = function(fn) coroutine.wrap(fn)() end,
	wait = function() return 1 end,
	delay = function() end,
}

TweenInfo = { new = function() return {} end }

HEARTBEAT = newSignal()
services.RunService = { Heartbeat = HEARTBEAT, BindToRenderStep = function() end }
services.Lighting = services.Lighting or {}
services.Players = services.Players or {}

function __pulse(n, dt)
	for _ = 1, n do
		HEARTBEAT:Fire(dt)
	end
end
`;

if (process.argv.includes('--boot')) {
  await lua.execute(BOOT_EXTRA);
  lua.globals.set('script', nodeByName['server']);
  const initFn = lua.load(src('src/server/init.server.luau'), { name: '@src/server/init.server.luau' });
  initFn.call();
  console.log('init.server.luau loaded without errors');
  const wrappedBoot = 'local print = log\n' + src('tests/boot_test.luau');
  const bootFn = lua.load(wrappedBoot, { name: '@boot_test' });
  bootFn.call();
  const bootLogs = await lua.execute('return table.concat(LOG, "\\n")');
  console.log(String(bootLogs[0] ?? ''));
  console.log('BOOT SCENARIO OK');
  process.exit(process.exitCode || 0);
}

// ---------- run the scenario ----------
try {
  let scenarioSrc = "local print = log\n" + src(scenarioPath);
  if (noDefenses) scenarioSrc = "SKIP_DEFENSES = true\n" + scenarioSrc;
  const wrapped = 'local ok, err = pcall(function()\n' + scenarioSrc + '\nend)\nif not ok then error(tostring(err) .. "\\n" .. debug.traceback(err, 2), 0) end';
  const fn = lua.load(wrapped, { name: '@scenario' });
  fn.call();
} catch (err) {
  console.error('SCENARIO FAILED: ' + String(err.message || err).slice(0, 600));
  process.exitCode = 1;
}
const logs = await lua.execute('return table.concat(LOG, "\\n")');
console.log(String(logs[0] ?? ''));
