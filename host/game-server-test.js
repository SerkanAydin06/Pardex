"use strict";
// The panel calls a table server ready only when its port answers: an old
// Korsan build printed PARDEX_GAME_SERVER_READY and then closed the server.
// Exported builds get no scene path (they refuse one).
const assert = require("assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { _test: host } = require("./pardex_host");

const folder = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-game-"));

function fakeGame(name, body) {
  const file = path.join(folder, name);
  fs.writeFileSync(file, `#!${process.execPath}\n${body}\n`);
  fs.chmodSync(file, 0o755);
  return file;
}

async function run() {
  if (process.platform === "win32") {
    console.log("Host game server test skipped on Windows");
    return;
  }
  const args = path.join(folder, "args.json");
  const good = fakeGame("good-game", `
require("fs").writeFileSync(${JSON.stringify(args)}, JSON.stringify(process.argv.slice(2)));
const port = Number(process.argv.find((a) => a.startsWith("--pardex-port=")).split("=")[1]);
console.log("PARDEX_GAME_SERVER_READY");
require("net").createServer(() => {}).listen(port, "127.0.0.1");
setTimeout(() => process.exit(0), 4000);`);
  const closing = fakeGame("old-game", `
console.log("PARDEX_GAME_SERVER_READY");
setTimeout(() => process.exit(0), 4000);`);
  host.setGameReadyGrace(1500);
  try {
    host.setConfig({ korsan_source: "project", korsan_exe: good, game_token: "x".repeat(40) });
    await host.startGameServer(3);
    const passed = JSON.parse(fs.readFileSync(args, "utf8"));
    assert.equal(passed[0], "--headless");
    assert.equal(passed.some((arg) => arg.startsWith("res://")), false, "no scene path for an exported build");
    assert.ok(passed.includes("--pardex-dedicated"));

    host.setConfig({ korsan_exe: closing });
    await assert.rejects(host.startGameServer(2), /eski olabilir/);
  } finally {
    await host.stopServer();
    fs.rmSync(folder, { recursive: true, force: true });
  }
  console.log("Host game server test passed: ready means the port answers; no scene path for exported builds");
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
