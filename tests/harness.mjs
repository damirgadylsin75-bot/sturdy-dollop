// Headless Luau runner: runs the actual game modules in real Luau (WASM)
// with the Roblox API stubbed out. Catches runtime/logic errors without Studio.
// Usage: node tests/harness.mjs <repo> [scenario.luau]   (default: drivetrain_test)
import fs from 'fs';
import path from 'path';
import * as luau from '@luau-rs/luau';

const repo = process.argv[2];
const scenarioPath = process.argv[3] || 'tests/drivetrain_test.luau';
const src = (p) => fs.readFileSync(path.join(repo, p), 'utf8');

const lua = await luau.Lua.create({});
lua.loadLibraries('all');

// deterministic math.random for reproducible runs
await lua.execute('math.randomseed(20261023)');

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
    return s % (b - a + 1) + a
  end
  return rng
end

NODES = {}
registry = {}
local function node(name)
  local n = { Name = name }
  NODES[name] = n
  return n
end

NODE_shared = node("Shared")
for _, name in ipairs(SHARED_MODULES) do
  local n = node(name)
  n.Parent = NODE_shared
  NODE_shared[name] = n
end

local RS = { Name = "ReplicatedStorage", Shared = NODE_shared }
services = { ReplicatedStorage = RS }
game = { GetService = function(_, name) return services[name] end }
require = function(target)
  local mod = registry[target]
  if mod == nil then error("module not registered for this node", 2) end
  return mod
end

LOG = {}
function log(msg) LOG[#LOG + 1] = tostring(msg) end
`;

await lua.execute(`
SHARED_MODULES = {}
`);
for (const f of fs.readdirSync(path.join(repo, 'src/shared')).sort()) {
  if (f.endsWith('.luau')) {
    const name = f.replace(/\.luau$/, '');
    await lua.execute(`SHARED_MODULES[#SHARED_MODULES + 1] = ${JSON.stringify(name)}`);
  }
}
await lua.execute(BOOTSTRAP);

// load every shared module (they must be stub-free, Roblox API not available here)
function loadModule(nodeName, relPath) {
  const nodeTable = lua.execute(`return NODES[${JSON.stringify(nodeName)}]`)[0];
  lua.globals.set('script', nodeTable);
  const fn = lua.load(src(relPath), { name: '@' + relPath });
  const results = fn.call();
  lua.globals.set('__MOD', results[0] ?? null);
  lua.globals.set('__NODE', nodeTable);
  lua.execute('registry[__NODE] = __MOD');
}

for (const f of fs.readdirSync(path.join(repo, 'src/shared')).sort()) {
  if (f.endsWith('.luau')) {
    loadModule(f.replace(/\.luau$/, ''), 'src/shared/' + f);
  }
}
console.log('all shared modules loaded: ' + fs.readdirSync(path.join(repo, 'src/shared')).filter(f => f.endsWith('.luau')).join(', '));

// ---------- run the scenario ----------
try {
  let scenarioSrc = "local print = log\n" + src(scenarioPath);
  const wrapped = 'local ok, err = pcall(function()\n' + scenarioSrc + '\nend)\nif not ok then error(tostring(err) .. "\\n" .. debug.traceback(err, 2), 0) end';
  const fn = lua.load(wrapped, { name: '@scenario' });
  fn.call();
} catch (err) {
  console.error('SCENARIO FAILED: ' + String(err.message || err).slice(0, 600));
  process.exitCode = 1;
}
const logs = await lua.execute('return table.concat(LOG, "\\n")');
console.log(String(logs[0] ?? ''));
