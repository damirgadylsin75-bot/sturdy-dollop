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
process.exit(bad ? 1 : 0);
