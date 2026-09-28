const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9888;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const GAME_SERVER_TOKEN = "pardex-production-guard-smoke-game-server-token-2026";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-production-guard:${value}`).digest("hex");
}

function waitForMessage(ws, predicate, timeoutMs = 5000) {
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

async function connectClient(name) {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  ws.send(JSON.stringify({ type: "hello", display_name: name, identity_key: identityKeyFor(name) }));
  const welcome = await welcomePromise;
  return { ws, userId: welcome.user_id };
}

async function createTwoPlayerRoom(host, joiner) {
  const createdPromise = waitForMessage(host.ws, (message) =>
    message.type === "room_state" && message.room?.members?.length === 1
  );
  host.ws.send(JSON.stringify({ type: "create_room", game_id: "korsanlar", max_players: 4 }));
  const created = await createdPromise;
  const code = created.room.code;

  const hostSeesJoin = waitForMessage(host.ws, (message) =>
    message.type === "room_state" && message.room?.code === code && message.room?.members?.length === 2
  );
  const joinerSeesRoom = waitForMessage(joiner.ws, (message) =>
    message.type === "room_state" && message.room?.code === code && message.room?.members?.length === 2
  );
  joiner.ws.send(JSON.stringify({ type: "join_room", code }));
  await Promise.all([hostSeesJoin, joinerSeesRoom]);

  const hostReadySeen = waitForMessage(joiner.ws, (message) =>
    message.type === "room_state"
    && message.room?.members?.find((member) => member.user_id === host.userId)?.ready === true
  );
  host.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
  await hostReadySeen;

  const joinerReadySeen = waitForMessage(host.ws, (message) =>
    message.type === "room_state"
    && message.room?.members?.find((member) => member.user_id === joiner.userId)?.ready === true
  );
  joiner.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
  await joinerReadySeen;
  return code;
}

async function closeClient(client) {
  const ws = client?.ws;
  if (!ws || ws.readyState === WebSocket.CLOSED) return;
  const done = new Promise((resolve) => ws.once("close", resolve));
  ws.close();
  await done;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-production-guard-"));
  const server = spawn(process.execPath, ["production_server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      KORSAN_GAME_SERVER_URL: GAME_SERVER_URL,
      PARDEX_GAME_SERVER_TOKEN: GAME_SERVER_TOKEN,
      PARDEX_SOCIAL_DATA_PATH: path.join(tempDir, "social.json"),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));

  let hostA;
  let joinerA;
  let hostB;
  let joinerB;
  try {
    await waitForServerReady(server);
    hostA = await connectClient("Guard-Host-A");
    joinerA = await connectClient("Guard-Joiner-A");
    hostB = await connectClient("Guard-Host-B");
    joinerB = await connectClient("Guard-Joiner-B");

    const roomA = await createTwoPlayerRoom(hostA, joinerA);
    const startAHost = waitForMessage(hostA.ws, (message) => message.type === "game_start");
    const startAJoiner = waitForMessage(joinerA.ws, (message) => message.type === "game_start");
    hostA.ws.send(JSON.stringify({ type: "start_game" }));
    const [launchA] = await Promise.all([startAHost, startAJoiner]);
    assert.strictEqual(launchA.room.state, "launching");

    const legacyEndRejected = waitForMessage(hostA.ws, (message) =>
      message.type === "error" && message.code === "GAME_SERVER_AUTHORITATIVE_REQUIRED"
    );
    hostA.ws.send(JSON.stringify({
      type: "game_ended",
      match_id: launchA.match_id,
      result: { reason: "forged-client-end" },
    }));
    await legacyEndRejected;

    await createTwoPlayerRoom(hostB, joinerB);
    const busyRejected = waitForMessage(hostB.ws, (message) =>
      message.type === "error" && message.code === "GAME_SERVER_BUSY"
    );
    hostB.ws.send(JSON.stringify({ type: "start_game" }));
    await busyRejected;

    const rollbackSeen = waitForMessage(joinerA.ws, (message) =>
      message.type === "room_state" && message.room?.code === roomA && message.room?.state === "lobby"
    );
    hostA.ws.send(JSON.stringify({
      type: "launch_failed",
      match_id: launchA.match_id,
      reason: "guard-smoke-rollback",
    }));
    await rollbackSeen;

    const startBA = waitForMessage(hostB.ws, (message) => message.type === "game_start");
    const startBB = waitForMessage(joinerB.ws, (message) => message.type === "game_start");
    hostB.ws.send(JSON.stringify({ type: "start_game" }));
    const [launchB] = await Promise.all([startBA, startBB]);
    assert.strictEqual(launchB.room.state, "launching");

    console.log("PARDEX production guard smoke passed: client end blocked + single-instance busy guard + rollback release");
  } finally {
    await closeClient(hostA);
    await closeClient(joinerA);
    await closeClient(hostB);
    await closeClient(joinerB);
    server.kill("SIGTERM");
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
