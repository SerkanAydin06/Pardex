const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9882;
const URL = `ws://127.0.0.1:${PORT}`;
const HELLO_TIMEOUT_MS = 800;

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-hardening:${value}`).digest("hex");
}

function waitForMessage(ws, predicate, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.off("message", onMessage);
      reject(new Error("Timed out waiting for WebSocket message"));
    }, timeoutMs);
    function onMessage(raw) {
      let payload;
      try {
        payload = JSON.parse(raw.toString("utf8"));
      } catch {
        return;
      }
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

async function openSocket() {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
  return ws;
}

async function connectClient(name) {
  const ws = await openSocket();
  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  ws.send(JSON.stringify({
    type: "hello",
    display_name: name,
    identity_key: identityKeyFor(name),
    presence_status: "online",
  }));
  const welcome = await welcomePromise;
  return { ws, accountId: welcome.account_id, userId: welcome.user_id };
}

async function closeClient(ws) {
  if (!ws || ws.readyState === WebSocket.CLOSED) return;
  const done = new Promise((resolve) => ws.once("close", resolve));
  ws.close();
  await done;
}

function waitForClose(ws, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Timed out waiting for socket close")), timeoutMs);
    ws.once("close", (code) => {
      clearTimeout(timeout);
      resolve(code);
    });
  });
}

async function fetchHealth() {
  const response = await fetch(`http://127.0.0.1:${PORT}/health`);
  return response.json();
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-hardening-smoke-"));
  const server = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      HELLO_TIMEOUT_MS: String(HELLO_TIMEOUT_MS),
      PARDEX_SOCIAL_DATA_PATH: path.join(tempDir, "social.json"),
      PARDEX_VOICE_RELAY_ENABLED: "",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    await waitForServerReady(server);

    // A socket that never says hello is closed after the hello timeout.
    const silent = await openSocket();
    const closeCode = await waitForClose(silent, HELLO_TIMEOUT_MS + 3000);
    assert.strictEqual(closeCode, 1008);

    // A socket that says hello in time is not affected by the timeout.
    const alice = await connectClient("Alice");
    await new Promise((resolve) => setTimeout(resolve, HELLO_TIMEOUT_MS + 300));
    assert.strictEqual(alice.ws.readyState, WebSocket.OPEN);

    // A second hello cannot switch the session to another account.
    const accountChangeError = waitForMessage(
      alice.ws,
      (message) => message.type === "error" && message.code === "ACCOUNT_CHANGE_NOT_ALLOWED"
    );
    alice.ws.send(JSON.stringify({ type: "hello", display_name: "Mallory", identity_key: identityKeyFor("Mallory") }));
    await accountChangeError;

    // Same account may still re-send hello (e.g. display name update).
    const renamed = waitForMessage(alice.ws, (message) => message.type === "welcome");
    alice.ws.send(JSON.stringify({ type: "hello", display_name: "Alice2", identity_key: identityKeyFor("Alice") }));
    const renamedWelcome = await renamed;
    assert.strictEqual(renamedWelcome.account_id, alice.accountId);
    assert.strictEqual(renamedWelcome.user_id, alice.userId);
    assert.strictEqual(renamedWelcome.display_name, "Alice2");

    // Voice relay is disabled by default.
    const health = await fetchHealth();
    assert.strictEqual(health.voiceRelay, false);

    const bob = await connectClient("Bob");
    const created = waitForMessage(alice.ws, (message) => message.type === "room_state");
    alice.ws.send(JSON.stringify({ type: "create_room", game_id: "korsanlar", max_players: 4 }));
    const code = (await created).room.code;
    const joined = waitForMessage(alice.ws, (message) => message.type === "room_state" && message.room.members.length === 2);
    bob.ws.send(JSON.stringify({ type: "join_room", code }));
    await joined;

    let relayed = false;
    alice.ws.on("message", (raw) => {
      if (JSON.parse(raw.toString("utf8")).type === "voice_frame") relayed = true;
    });
    bob.ws.send(JSON.stringify({ type: "voice_frame", seq: 1, pcm: "AQIDBA==" }));
    const pong = waitForMessage(bob.ws, (message) => message.type === "pong");
    bob.ws.send(JSON.stringify({ type: "ping" }));
    await pong;
    await new Promise((resolve) => setTimeout(resolve, 200));
    assert.strictEqual(relayed, false);

    console.log("PARDEX hardening smoke test passed: hello timeout -> account lock -> voice relay off");

    await closeClient(alice.ws);
    await closeClient(bob.ws);
  } finally {
    server.kill("SIGTERM");
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
