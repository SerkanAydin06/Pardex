const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9876;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const SESSION_GRACE_MS = 1200;

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-smoke:${value}`).digest("hex");
}

function waitForMessage(ws, predicate, timeoutMs = 4000) {
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

async function connectClient(displayName, resumeToken = "", expectRoom = false, identityKey = identityKeyFor(displayName)) {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });

  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  const roomPromise = expectRoom
    ? waitForMessage(ws, (message) => message.type === "room_state")
    : null;
  const hello = {
    type: "hello",
    display_name: displayName,
    identity_key: identityKey,
  };
  if (resumeToken) hello.resume_token = resumeToken;
  ws.send(JSON.stringify(hello));

  const welcome = await welcomePromise;
  const roomState = roomPromise ? await roomPromise : null;
  assert.ok(welcome.user_id, "welcome must include user_id");
  assert.ok(welcome.account_id, "welcome must include persistent account_id");
  assert.ok(welcome.resume_token, "welcome must include resume_token");
  assert.strictEqual(welcome.display_name, displayName);
  return {
    ws,
    userId: welcome.user_id,
    accountId: welcome.account_id,
    resumeToken: welcome.resume_token,
    resumed: Boolean(welcome.resumed),
    roomState,
    identityKey,
  };
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

async function closeClient(ws) {
  if (!ws || ws.readyState === WebSocket.CLOSED) return;
  const closed = new Promise((resolve) => ws.once("close", resolve));
  ws.close();
  await closed;
}

async function setReadyAndWait(client, observer, userId) {
  const readyPromise = waitForMessage(
    observer.ws,
    (message) => message.type === "room_state"
      && message.room?.members?.some((member) => member.user_id === userId && member.ready === true)
  );
  client.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
  await readyPromise;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-room-smoke-"));
  const socialDataPath = path.join(tempDir, "social.json");
  const server = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      KORSAN_GAME_SERVER_URL: GAME_SERVER_URL,
      SESSION_GRACE_MS: String(SESSION_GRACE_MS),
      PARDEX_SOCIAL_DATA_PATH: socialDataPath,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  server.stderr.on("data", (chunk) => process.stderr.write(chunk));

  let first;
  let second;
  try {
    await waitForServerReady(server);
    first = await connectClient("Pardus-A");
    second = await connectClient("Pardus-B");

    assert.strictEqual(first.resumed, false);
    assert.strictEqual(second.resumed, false);
    assert.notStrictEqual(first.accountId, second.accountId);

    const createdPromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state" && message.room?.members?.length === 1
    );
    first.ws.send(JSON.stringify({
      type: "create_room",
      game_id: "korsanlar",
      max_players: 4,
    }));
    const created = await createdPromise;
    const roomCode = created.room.code;
    const originalHostId = first.userId;
    const hostResumeToken = first.resumeToken;
    assert.match(roomCode, /^[A-Z2-9]{5}$/);
    assert.strictEqual(created.room.host_id, originalHostId);
    assert.strictEqual(created.room.game_server_url, GAME_SERVER_URL);
    assert.strictEqual(created.room.members[0].account_id, first.accountId);

    const firstJoinPromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state" && message.room?.members?.length === 2
    );
    const secondJoinPromise = waitForMessage(
      second.ws,
      (message) => message.type === "room_state" && message.room?.members?.length === 2
    );
    second.ws.send(JSON.stringify({ type: "join_room", code: roomCode }));
    const [, secondJoined] = await Promise.all([firstJoinPromise, secondJoinPromise]);
    assert.ok(secondJoined.room.members.some((member) => member.account_id === second.accountId));

    await setReadyAndWait(first, second, originalHostId);

    await closeClient(first.ws);
    first = await connectClient("Pardus-A", hostResumeToken, true, first.identityKey);
    assert.strictEqual(first.resumed, true, "host connection should resume");
    assert.strictEqual(first.userId, originalHostId, "resumed host must keep user_id");
    assert.strictEqual(first.resumeToken, hostResumeToken, "resume token should remain stable");
    assert.strictEqual(first.roomState.room.code, roomCode);
    assert.strictEqual(first.roomState.room.host_id, originalHostId, "host role must survive reconnect");
    assert.ok(
      first.roomState.room.members.some(
        (member) => member.user_id === originalHostId && member.ready === true
      ),
      "ready state must survive reconnect"
    );

    const mutedStatePromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state"
        && message.room?.members?.some(
          (member) => member.user_id === second.userId && member.voice_muted === true
        )
    );
    second.ws.send(JSON.stringify({ type: "voice_state", muted: true }));
    await mutedStatePromise;

    const unmutedStatePromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state"
        && message.room?.members?.some(
          (member) => member.user_id === second.userId && member.voice_muted === false
        )
    );
    second.ws.send(JSON.stringify({ type: "voice_state", muted: false }));
    await unmutedStatePromise;

    const voiceRelayPromise = waitForMessage(
      first.ws,
      (message) => message.type === "voice_frame"
        && message.user_id === second.userId
        && message.seq === 7
        && message.pcm === "AQIDBA=="
    );
    second.ws.send(JSON.stringify({
      type: "voice_frame",
      seq: 7,
      pcm: "AQIDBA==",
    }));
    await voiceRelayPromise;

    await setReadyAndWait(second, first, second.userId);

    const firstStartPromise = waitForMessage(first.ws, (message) => message.type === "game_start");
    const secondStartPromise = waitForMessage(second.ws, (message) => message.type === "game_start");
    first.ws.send(JSON.stringify({ type: "start_game" }));
    const [firstStart, secondStart] = await Promise.all([firstStartPromise, secondStartPromise]);

    assert.strictEqual(firstStart.room.code, roomCode);
    assert.strictEqual(secondStart.room.code, roomCode);
    assert.strictEqual(firstStart.room.game_server_url, GAME_SERVER_URL);
    assert.strictEqual(firstStart.room.launching, true);
    assert.strictEqual(secondStart.room.launching, true);

    const hostRollbackPromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state"
        && message.room?.code === roomCode
        && message.room.launching === false
        && message.room.members.some((member) => member.user_id === second.userId && member.ready === false)
    );
    const joinerRollbackPromise = waitForMessage(
      second.ws,
      (message) => message.type === "room_state"
        && message.room?.code === roomCode
        && message.room.launching === false
    );
    second.ws.send(JSON.stringify({ type: "launch_failed" }));
    await Promise.all([hostRollbackPromise, joinerRollbackPromise]);

    const expiredMemberPromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state"
        && message.room?.code === roomCode
        && message.room.members.length === 1
        && message.room.members[0].user_id === originalHostId,
      SESSION_GRACE_MS + 2500
    );
    await closeClient(second.ws);
    await expiredMemberPromise;

    console.log(
      "PARDEX Online smoke test passed: identity -> create -> join -> reconnect recovery -> voice -> ready -> start -> rollback -> expiry"
    );
  } finally {
    if (first?.ws) first.ws.close();
    if (second?.ws) second.ws.close();
    server.kill("SIGTERM");
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
