const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9881;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-presence:${value}`).digest("hex");
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

function friendFromState(message, accountId) {
  return message.state?.friends?.find((friend) => friend.account_id === accountId);
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-presence-smoke-"));
  const server = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      KORSAN_GAME_SERVER_URL: GAME_SERVER_URL,
      PARDEX_SOCIAL_DATA_PATH: path.join(tempDir, "social.json"),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    await waitForServerReady(server);

    const early = await openSocket();
    const earlyError = waitForMessage(early, (message) => message.type === "error" && message.code === "SESSION_NOT_READY");
    early.send(JSON.stringify({ type: "get_social_state" }));
    await earlyError;
    await closeClient(early);

    const alice = await connectClient("Alice");
    const bob = await connectClient("Bob");

    const requestSeen = waitForMessage(alice.ws, (message) =>
      message.type === "social_state"
      && message.state?.incoming_requests?.some((profile) => profile.account_id === bob.accountId)
    );
    bob.ws.send(JSON.stringify({ type: "send_friend_request", account_id: alice.accountId }));
    await requestSeen;

    const aliceFriendState = waitForMessage(alice.ws, (message) =>
      message.type === "social_state" && Boolean(friendFromState(message, bob.accountId))
    );
    const bobFriendState = waitForMessage(bob.ws, (message) =>
      message.type === "social_state" && Boolean(friendFromState(message, alice.accountId))
    );
    alice.ws.send(JSON.stringify({ type: "accept_friend_request", account_id: bob.accountId }));
    await aliceFriendState;
    await bobFriendState;

    const bobBusySeen = waitForMessage(alice.ws, (message) => {
      if (message.type !== "social_state") return false;
      return friendFromState(message, bob.accountId)?.presence === "busy";
    });
    bob.ws.send(JSON.stringify({ type: "set_presence", presence: "busy" }));
    await bobBusySeen;

    const aliceRoomPromise = waitForMessage(alice.ws, (message) => message.type === "room_state" && message.room?.game_id === "korsanlar");
    const aliceRoomSeenByBob = waitForMessage(bob.ws, (message) => {
      if (message.type !== "social_state") return false;
      const friend = friendFromState(message, alice.accountId);
      return friend?.in_room === true
        && friend?.room_state === "lobby"
        && friend?.game_name === "Korsanların Hazinesi"
        && friend?.room_joinable === true;
    });
    alice.ws.send(JSON.stringify({ type: "create_room", game_id: "korsanlar", max_players: 4 }));
    const aliceRoom = await aliceRoomPromise;
    await aliceRoomSeenByBob;
    assert.ok(aliceRoom.room.code, "room must have a code");
    assert.strictEqual(aliceRoom.room.state, "lobby");

    const bobJoined = waitForMessage(bob.ws, (message) =>
      message.type === "room_state"
      && message.room?.members?.some((member) => member.account_id === alice.accountId)
      && message.room?.members?.some((member) => member.account_id === bob.accountId)
    );
    bob.ws.send(JSON.stringify({ type: "join_friend_room", account_id: alice.accountId }));
    const joinedRoom = await bobJoined;
    assert.strictEqual(joinedRoom.room.code, aliceRoom.room.code, "friend join must enter the same room");

    const aliceReadySeen = waitForMessage(bob.ws, (message) =>
      message.type === "room_state"
      && message.room?.members?.find((member) => member.account_id === alice.accountId)?.ready === true
    );
    alice.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
    await aliceReadySeen;

    const bobReadySeen = waitForMessage(alice.ws, (message) =>
      message.type === "room_state"
      && message.room?.members?.find((member) => member.account_id === bob.accountId)?.ready === true
    );
    bob.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
    await bobReadySeen;

    const gameStart = waitForMessage(bob.ws, (message) => message.type === "game_start");
    alice.ws.send(JSON.stringify({ type: "start_game" }));
    const started = await gameStart;
    const matchId = started.match_id || started.room?.match_id;
    assert.ok(matchId, "game_start must include match_id");
    assert.strictEqual(started.room.state, "launching");
    assert.strictEqual(started.room.in_game, false);

    const bobInGameSeen = waitForMessage(alice.ws, (message) => {
      if (message.type !== "social_state") return false;
      const friend = friendFromState(message, bob.accountId);
      return friend?.presence === "in_game"
        && friend?.in_game === true
        && friend?.room_state === "in_game"
        && friend?.room_joinable === false;
    });
    alice.ws.send(JSON.stringify({ type: "game_connected", match_id: matchId }));
    bob.ws.send(JSON.stringify({ type: "game_connected", match_id: matchId }));
    await bobInGameSeen;

    console.log("PARDEX presence smoke test passed: session guard -> status -> activity -> friend join -> launching -> confirmed in-game");

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
