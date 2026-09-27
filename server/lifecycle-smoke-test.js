const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9883;
const URL = `ws://127.0.0.1:${PORT}`;
const HEALTH_URL = `http://127.0.0.1:${PORT}/health`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-lifecycle:${value}`).digest("hex");
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

async function connectClient(name) {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  ws.send(JSON.stringify({
    type: "hello",
    display_name: name,
    identity_key: identityKeyFor(name),
  }));
  const welcome = await welcomePromise;
  assert.strictEqual(welcome.room_lifecycle_enabled, true);
  return {
    ws,
    userId: welcome.user_id,
    accountId: welcome.account_id,
  };
}

async function closeClient(ws) {
  if (!ws || ws.readyState === WebSocket.CLOSED) return;
  const done = new Promise((resolve) => ws.once("close", resolve));
  ws.close();
  await done;
}

async function ready(client, observer, userId) {
  const seen = waitForMessage(observer.ws, (message) =>
    message.type === "room_state"
    && message.room?.members?.find((member) => member.user_id === userId)?.ready === true
  );
  client.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
  await seen;
}

async function startMatch(host, joiner) {
  await ready(host, joiner, host.userId);
  await ready(joiner, host, joiner.userId);

  const hostStart = waitForMessage(host.ws, (message) => message.type === "game_start");
  const joinerStart = waitForMessage(joiner.ws, (message) => message.type === "game_start");
  host.ws.send(JSON.stringify({ type: "start_game" }));
  const [hostPayload, joinerPayload] = await Promise.all([hostStart, joinerStart]);

  assert.strictEqual(hostPayload.room.state, "launching");
  assert.strictEqual(hostPayload.room.launching, true);
  assert.strictEqual(hostPayload.room.in_game, false);
  assert.ok(hostPayload.match_id, "game_start must expose match_id");
  assert.strictEqual(hostPayload.match_id, joinerPayload.match_id);
  assert.strictEqual(hostPayload.match_id, hostPayload.room.match_id);
  assert.ok(hostPayload.room.launch_started_at > 0);
  assert.strictEqual(hostPayload.room.started_at, 0);
  assert.ok(hostPayload.room.members.every((member) => member.game_state === "launching"));
  return hostPayload.match_id;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-lifecycle-smoke-"));
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
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));

  let host;
  let joiner;
  let outsider;
  try {
    await waitForServerReady(server);
    const health = await fetch(HEALTH_URL).then((response) => response.json());
    assert.strictEqual(health.roomLifecycle, true);
    assert.deepStrictEqual(health.roomLifecycleCounts, {
      lobby: 0,
      launching: 0,
      in_game: 0,
      ended: 0,
    });

    host = await connectClient("Lifecycle-Host");
    joiner = await connectClient("Lifecycle-Joiner");
    outsider = await connectClient("Lifecycle-Outsider");

    const createdPromise = waitForMessage(host.ws, (message) =>
      message.type === "room_state" && message.room?.members?.length === 1
    );
    host.ws.send(JSON.stringify({ type: "create_room", game_id: "korsanlar", max_players: 4 }));
    const created = await createdPromise;
    const roomCode = created.room.code;
    assert.strictEqual(created.room.state, "lobby");
    assert.strictEqual(created.room.match_id, "");
    assert.strictEqual(created.room.launching, false);
    assert.strictEqual(created.room.in_game, false);
    assert.strictEqual(created.room.ended, false);
    assert.strictEqual(created.room.members[0].game_state, "lobby");
    assert.strictEqual(created.room.members[0].connection_state, "online");

    const hostSeesJoin = waitForMessage(host.ws, (message) =>
      message.type === "room_state" && message.room?.members?.length === 2
    );
    const joinerJoined = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state" && message.room?.code === roomCode && message.room?.members?.length === 2
    );
    joiner.ws.send(JSON.stringify({ type: "join_room", code: roomCode }));
    await Promise.all([hostSeesJoin, joinerJoined]);

    const firstMatchId = await startMatch(host, joiner);

    const staleMatchError = waitForMessage(host.ws, (message) =>
      message.type === "error" && message.code === "MATCH_MISMATCH"
    );
    host.ws.send(JSON.stringify({ type: "game_connected", match_id: crypto.randomUUID() }));
    await staleMatchError;

    const hostConnectedSeen = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state"
      && message.room?.state === "launching"
      && message.room.members.find((member) => member.user_id === host.userId)?.game_state === "in_game"
      && message.room.members.find((member) => member.user_id === joiner.userId)?.game_state === "launching"
    );
    host.ws.send(JSON.stringify({ type: "game_connected", match_id: firstMatchId }));
    await hostConnectedSeen;

    const hostGameStarted = waitForMessage(host.ws, (message) =>
      message.type === "game_started" && message.match_id === firstMatchId
    );
    const joinerInGameState = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state" && message.room?.state === "in_game"
    );
    joiner.ws.send(JSON.stringify({ type: "game_connected", match_id: firstMatchId }));
    const [, inGameState] = await Promise.all([hostGameStarted, joinerInGameState]);
    assert.strictEqual(inGameState.room.launching, false);
    assert.strictEqual(inGameState.room.in_game, true);
    assert.ok(inGameState.room.started_at > 0);
    assert.ok(inGameState.room.members.every((member) => member.game_state === "in_game"));

    const outsiderJoinRejected = waitForMessage(outsider.ws, (message) =>
      message.type === "error" && message.code === "ROOM_IN_GAME"
    );
    outsider.ws.send(JSON.stringify({ type: "join_room", code: roomCode }));
    await outsiderJoinRejected;

    const nonHostEndRejected = waitForMessage(joiner.ws, (message) =>
      message.type === "error" && message.code === "NOT_HOST"
    );
    joiner.ws.send(JSON.stringify({ type: "game_ended", match_id: firstMatchId }));
    await nonHostEndRejected;

    const hostEnded = waitForMessage(host.ws, (message) =>
      message.type === "game_ended" && message.match_id === firstMatchId
    );
    const joinerEndedState = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state" && message.room?.state === "ended"
    );
    host.ws.send(JSON.stringify({
      type: "game_ended",
      match_id: firstMatchId,
      result: { reason: "smoke_complete", winner_account_id: host.accountId },
    }));
    const [endedEvent, endedState] = await Promise.all([hostEnded, joinerEndedState]);
    assert.strictEqual(endedState.room.ended, true);
    assert.strictEqual(endedState.room.in_game, false);
    assert.ok(endedState.room.ended_at > 0);
    assert.ok(endedState.room.members.every((member) => member.ready === false));
    assert.ok(endedState.room.members.every((member) => member.game_state === "ended"));
    assert.strictEqual(endedEvent.result.reason, "smoke_complete");

    const nonHostLobbyRejected = waitForMessage(joiner.ws, (message) =>
      message.type === "error" && message.code === "NOT_HOST"
    );
    joiner.ws.send(JSON.stringify({ type: "return_to_lobby" }));
    await nonHostLobbyRejected;

    const returnedToLobby = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state"
      && message.room?.state === "lobby"
      && message.room?.match_id === ""
    );
    host.ws.send(JSON.stringify({ type: "return_to_lobby" }));
    const lobbyState = await returnedToLobby;
    assert.ok(lobbyState.room.members.every((member) => member.game_state === "lobby"));
    assert.ok(lobbyState.room.members.every((member) => member.ready === false));

    const secondMatchId = await startMatch(host, joiner);
    const hostAbort = waitForMessage(host.ws, (message) =>
      message.type === "game_launch_aborted"
      && message.reason === "simulated_launch_failure"
      && message.failed_user_id === joiner.userId
    );
    const joinerRollback = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state"
      && message.room?.state === "lobby"
      && message.room?.match_id === ""
      && message.room.members.every((member) => member.ready === false)
    );
    joiner.ws.send(JSON.stringify({
      type: "launch_failed",
      match_id: secondMatchId,
      reason: "simulated_launch_failure",
    }));
    await Promise.all([hostAbort, joinerRollback]);

    const finalHealth = await fetch(HEALTH_URL).then((response) => response.json());
    assert.strictEqual(finalHealth.roomLifecycleCounts.lobby, 1);
    assert.strictEqual(finalHealth.roomLifecycleCounts.launching, 0);
    assert.strictEqual(finalHealth.roomLifecycleCounts.in_game, 0);
    assert.strictEqual(finalHealth.roomLifecycleCounts.ended, 0);

    console.log("PARDEX lifecycle smoke test passed: lobby -> launching -> in_game -> ended -> lobby + launch rollback");
  } finally {
    await closeClient(host?.ws);
    await closeClient(joiner?.ws);
    await closeClient(outsider?.ws);
    server.kill("SIGTERM");
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
