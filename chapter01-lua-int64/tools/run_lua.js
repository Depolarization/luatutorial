// 用 fengari（Lua VM，纯 JS）在本机跑 src/demo.lua，把真实输出落盘
// 注意：fengari 是 Lua 5.3，不带 bit32 —— 用 src/bit32_pure.lua 兼容层补上
const fs = require("fs");
const path = require("path");
const f = require("fengari");
const { to_luastring } = require("fengari/src/fengaricore.js");

const ROOT = path.resolve(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(ROOT, "src", p), "utf8");

const prelude = `
bit32 = (function() ${read("bit32_pure.lua")} end)()
package.preload["int64"] = function() ${read("int64.lua")} end
package.preload["vectors"] = function() ${read("vectors.lua")} end
`;

const L = f.lauxlib.luaL_newstate();
f.lualib.luaL_openlibs(L);

let rc = f.lauxlib.luaL_dostring(L, to_luastring(prelude));
if (rc !== 0) { console.error("prelude 失败:", f.lua.lua_tojsstring(L, -1)); process.exit(1); }

for (const script of ["demo.lua", "test.lua"]) {
  rc = f.lauxlib.luaL_dostring(L, to_luastring(read(script)));
  if (rc !== 0) { console.error(script, "失败:", f.lua.lua_tojsstring(L, -1)); process.exit(1); }
}
