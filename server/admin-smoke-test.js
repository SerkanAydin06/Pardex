"use strict";
const assert = require("assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");
const { once } = require("events");
const WebSocket = require("ws");
const { SocialStore } = require("./social_store");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-admin-"));
const dataPath = path.join(dir, "social.json");
const token = crypto.randomBytes(32).toString("hex");
let server;
const sockets = [];

function message(ws, type) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { ws.off("message", onMessage); reject(new Error(`Missing ${type}`)); }, 4000);
    function onMessage(raw) {
      const data = JSON.parse(raw);
      if (data.type !== type) return;
      clearTimeout(timer);
      ws.off("message", onMessage);
      resolve(data);
    }
    ws.on("message", onMessage);
  });
}

async function run() {
  const initial = new SocialStore(dataPath);
  const a = initial.ensureAccount("px_a", "İsim").account;
  const b = initial.ensureAccount("px_b", "isim").account;
  assert.equal(b.display_name, "isim_2");
  assert.equal(initial.ensureAccount("px_b", " İSİM ").nameTaken, true);
  assert.equal(b.display_name, "isim_2");
  assert.equal(initial.ensureAccount("px_a", "isim").nameTaken, false);
  assert.equal(a.display_name, "isim");
  initial.ensureAccount("px_c", "Ａda");
  assert.equal(initial.ensureAccount("px_d", "Ada").account.display_name, "Ada_2");
  const long = "x".repeat(24);
  initial.ensureAccount("px_long", long);
  assert.equal(initial.ensureAccount("px_long2", long).account.display_name.length, 24);
  initial.ensureAccount("px_free", "Free");
  assert.equal(initial.cleanupOrphanAccount("px_free"), true);
  assert.equal(initial.ensureAccount("px_free2", "Free").account.display_name, "Free");
  // Legacy migration reserves real names before assigning suffixes.
  b.display_name = "İSİM";
  a.created_at = 1;
  b.created_at = 2;
  initial.data.accounts.px_reserved = { ...a, display_name: "isim_2", created_at: 3, friends: [] };
  a.friends = ["px_b"];
  a.recovery_hash = "a".repeat(64);
  initial.save();
  const migrated = new SocialStore(dataPath);
  assert.equal(migrated.getAccount("px_a").display_name, "isim");
  assert.equal(migrated.getAccount("px_b").display_name, "İSİM_3");
  assert.deepEqual(migrated.getAccount("px_a").friends, ["px_b"]);
  assert.equal(migrated.getAccount("px_a").recovery_hash, "a".repeat(64));
  assert.equal(new SocialStore(dataPath).getAccount("px_b").display_name, "İSİM_3");

  // Real HTTP/WebSocket path: forbidden public access and unique online accounts.
  const port = 9892;
  server = spawn(process.execPath, ["production_server.js"], {
    cwd: __dirname, stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(port),
      PARDEX_SOCIAL_DATA_PATH: dataPath, PARDEX_ADMIN_TOKEN: token },
  });
  server.stderr.on("data", (data) => process.stderr.write(data));
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Server startup timeout")), 5000);
    server.stdout.on("data", (data) => {
      if (String(data).includes("PARDEX Online listening")) { clearTimeout(timer); resolve(); }
    });
    server.once("exit", (code) => { clearTimeout(timer); reject(new Error(`Server exited: ${code}`)); });
  });
  const endpoint = `http://127.0.0.1:${port}/admin/users`;
  assert.equal((await fetch(endpoint)).status, 403);
  assert.equal((await fetch(endpoint, { headers: { Authorization: "Bearer wrong" } })).status, 403);
  async function connect(name, identity) {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    sockets.push(ws);
    await once(ws, "open");
    const welcomed = message(ws, "welcome");
    ws.send(JSON.stringify({ type: "hello", display_name: name, identity_key: identity }));
    return { ws, welcome: await welcomed, identity };
  }
  const first = await connect("Pardus", crypto.randomBytes(32).toString("hex"));
  const second = await connect("Pardus", crypto.randomBytes(32).toString("hex"));
  assert.equal(first.welcome.display_name, "Pardus");
  assert.equal(second.welcome.display_name, "Pardus_2");
  await connect("Pardus", first.identity);
  const rejected = message(second.ws, "error");
  const welcomed = message(second.ws, "welcome");
  second.ws.send(JSON.stringify({ type: "hello", display_name: "Pardus", identity_key: second.identity }));
  assert.equal((await rejected).code, "NAME_TAKEN");
  assert.equal((await welcomed).display_name, "Pardus_2");
  const users = await (await fetch(endpoint, { headers: { Authorization: `Bearer ${token}` } })).json();
  assert.equal(users.online, 2, "multiple sockets must count as one account");
  assert.equal(users.total, Object.keys(new SocialStore(dataPath).data.accounts).length);
  for (const user of users.users) {
    assert.deepEqual(Object.keys(user).sort(), ["account_id", "display_name", "created_at", "updated_at", "friend_count", "online", "presence", "in_game"].sort());
  }
  for (const ws of sockets) ws.terminate();
  // Closing sockets must not leave recoverable sessions marked online.
  let offline;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    offline = await (await fetch(endpoint, { headers: { Authorization: `Bearer ${token}` } })).json();
    if (!offline.online) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  assert.equal(offline.online, 0);
  console.log("Name uniqueness and admin smoke test passed");
}

run().catch((error) => { console.error(error); process.exitCode = 1; }).finally(async () => {
  for (const ws of sockets) ws.terminate();
  if (server && server.exitCode === null) { const exited = once(server, "exit"); server.kill("SIGTERM"); await exited; }
  fs.rmSync(dir, { recursive: true, force: true });
});
