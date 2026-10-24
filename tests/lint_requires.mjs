// Lint: verifies every require() reference points at a file that exists.
// Rojo convention in this repo:
//   init.server.luau / init.client.luau own their folder -> siblings via script.X
//   regular modules -> siblings via script.Parent.X, shared via ReplicatedStorage.Shared.X
import fs from 'fs';
import path from 'path';

const root = path.resolve(process.argv[2] || '.');
let bad = 0;
const files = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.luau')) files.push(p);
  }
})(path.join(root, 'src'));

for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(root, f).replace(/\\/g, '/');
  const isInit = /init\.(server|client)\.luau$/.test(f);
  const dir = path.dirname(f);
  const refRe = /require\((script(?:\.Parent)?\.([A-Za-z0-9_]+)|ReplicatedStorage\.Shared\.([A-Za-z0-9_]+))\)/g;
  let m;
  while ((m = refRe.exec(src)) !== null) {
    const whole = m[1];
    const sib = m[2];
    const shared = m[3];
    if (shared) {
      if (!fs.existsSync(path.join(root, 'src/shared', shared + '.luau'))) {
        console.log(`BAD ${rel}: missing src/shared/${shared}.luau (${whole})`);
        bad++;
      }
      continue;
    }
    if (isInit && whole.startsWith('script.Parent')) {
      console.log(`BAD ${rel}: init script owns its folder — use script.${sib}, not script.Parent.${sib}`);
      bad++;
      continue;
    }
    if (!fs.existsSync(path.join(dir, sib + '.luau'))) {
      console.log(`BAD ${rel}: missing sibling ${sib}.luau (${whole})`);
      bad++;
    }
  }
}
console.log(bad ? `${bad} bad require(s)` : 'require graph OK');
if (bad > 0) process.exit(1);

// --- module return check: ModuleScript must return exactly one value ---
// Every .luau under src/ EXCEPT init.* (those are Scripts, not modules)
// must have a top-level `return` (column 0), otherwise require() throws
// "Module code did not return exactly one value" at runtime.
import { readdirSync, statSync } from 'fs';

function walk(dir) {
  let out = [];
  for (const f of readdirSync(dir)) {
    const full = dir + '/' + f;
    if (statSync(full).isDirectory()) out = out.concat(walk(full));
    else if (f.endsWith('.luau')) out.push(full);
  }
  return out;
}

let badRet = 0;
for (const file of walk('src')) {
  const base = file.split('/').pop();
  if (base.startsWith('init.')) continue; // Scripts, not modules
  const text = fs.readFileSync(file, 'utf8');
  if (!/^return\b/m.test(text)) {
    console.error(`${file}: module has no top-level return (require() will throw)`);
    badRet++;
  }
}
if (badRet > 0) process.exit(1);
console.log('module returns OK');
