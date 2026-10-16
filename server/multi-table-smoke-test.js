const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9893;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URLS = ["ws://127.0.0.1:9997", "ws://127.0.0.1:9998"];
const GAME_SERVER_TOKEN = "pardex-quick-play-smoke-game-server-token-2026-xx";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-multi:${value}`).digest("hex");
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function waitForMessage(ws, predicate, timeoutMs = 7000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.off("message", onMessage);
      reject(new Error("Timed out waiting for WebSocket message"));
    }, timeoutMs);
    function onMessage(raw) {
      let payload;
      try { payload = JSON.parse(raw.toString("utf8")); } catch { return; }
      if (!predicate(payload)) return;
      clearTimeout(timeout);
      ws.off("message", onMessage);
      resolve(payload);
    }
    ws.on("message", onMessage);
  });
}

async function waitForServerReady(server) {
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Server startup timeout")), 5000);
    server.stdout.on("data", (chunk) => {
      if (!chunk.toString("utf8").includes("PARDEX Online listening")) return;
      clearTimeout(timeout);
      resolve();
    });
    server.once("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`Server exited before ready with code ${code}`));
    });
  });
}

async function connectSocket() {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
  return ws;
}

async function connectClient(name) {
  const ws = await connectSocket();
  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  ws.send(JSON.stringify({ type: "hello", display_name: name, identity_key: identityKeyFor(name) }));
  const welcome = await welcomePromise;
  return { ws, userId: welcome.user_id, accountId: welcome.account_id };
}

async function closeSocket(ws) {
  if (!ws || ws.readyState === WebSocket.CLOSED) return;
  const done = new Promise((resolve) => ws.once("close", resolve));
  ws.close();
  await done;
}

async function play(client) {
  const start = waitForMessage(client.ws, (m) => m.type === "game_start" || (m.type === "error" && m.code === "GAME_SERVER_BUSY"));
  client.ws.send(JSON.stringify({ type: "play_game", game_id: "korsanlar" }));
  return start;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-multi-"));
  const server = spawn(process.execPath, ["production_server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      PARDEX_SOCIAL_DATA_PATH: path.join(tempDir, "social.json"),
      PARDEX_GAME_SERVER_TOKEN: GAME_SERVER_TOKEN,
      KORSAN_GAME_SERVER_URLS: GAME_SERVER_URLS.join(","),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));
  const sockets = [];
  try {
    await waitForServerReady(server);
    const players = [];
    for (const name of ["Multi-A", "Multi-B", "Multi-C"]) {
      const client = await connectClient(name);
      sockets.push(client.ws);
      players.push(client);
    }
    // Two strangers each get their own table on a different game server.
    const first = await play(players[0]);
    const second = await play(players[1]);
    assert.strictEqual(first.type, "game_start");
    assert.strictEqual(second.type, "game_start");
    assert.notStrictEqual(first.room.code, second.room.code);
    assert.deepStrictEqual(
      [first.room.game_server_url, second.room.game_server_url].sort(),
      GAME_SERVER_URLS
    );
    // Every server is busy now.
    const third = await play(players[2]);
    assert.strictEqual(third.type, "error");
    console.log("PARDEX multi-table smoke passed: one table per game server + busy when all servers are used");
  } finally {
    for (const ws of sockets) await closeSocket(ws);
    server.kill();
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
