// Lua 5.1-compatible syntax gate (subset of Luau). Full check runs in CI via luau-compile.
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const luaparse = require('luaparse');

const root = path.resolve(process.argv[2] || '..');
let bad = 0, ok = 0;
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.luau')) {
      try {
        luaparse.parse(fs.readFileSync(p, 'utf8'), { luaVersion: '5.1' });
        ok++;
      } catch (err) {
        bad++;
        console.log(`SYNTAX ERROR: ${p}:${err.line ?? '?'}: ${err.message}`);
      }
    }
  }
})(path.join(root, 'src'));
console.log(`checked ${ok} files, ${bad} with syntax errors`);
process.exit(bad ? 1 : 0);
