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
const CONTROL_HEALTH_URL = `http://127.0.0.1:${PORT}/game-control-health`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const GAME_SERVER_TOKEN = "pardex-lifecycle-smoke-game-server-token-2026";

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
  ws.send(JSON.stringify({ type: "hello", display_name: name, identity_key: identityKeyFor(name) }));
  const welcome = await welcomePromise;
  assert.strictEqual(welcome.room_lifecycle_enabled, true);
  assert.strictEqual(welcome.secure_game_handoff_enabled, true);
  return { ws, userId: welcome.user_id, accountId: welcome.account_id };
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
  assert.strictEqual(hostPayload.room.in_game, false);
  assert.ok(hostPayload.match_id);
  assert.strictEqual(hostPayload.match_id, joinerPayload.match_id);
  assert.ok(hostPayload.launch_ticket);
  assert.ok(joinerPayload.launch_ticket);
  assert.notStrictEqual(hostPayload.launch_ticket, joinerPayload.launch_ticket);
  assert.ok(hostPayload.room.members.every((member) => member.game_state === "launching"));
  return { hostPayload, joinerPayload, matchId: hostPayload.match_id };
}

async function verifyTicket(startPayload, ticket = startPayload.launch_ticket) {
  const ws = await openSocket();
  const response = waitForMessage(ws, (message) =>
    message.type === "game_ticket_ok" || message.type === "error"
  );
  ws.send(JSON.stringify({
    type: "game_ticket_verify",
    game_id: startPayload.game_id,
    match_id: startPayload.match_id,
    launch_ticket: ticket,
  }));
  return { ws, response: await response };
}

async function admitGame(verification, startPayload) {
  const response = waitForMessage(verification.ws, (message) =>
    message.type === "game_admitted_ok" || message.type === "error"
  );
  verification.ws.send(JSON.stringify({
    type: "game_admitted",
    game_id: startPayload.game_id,
    match_id: startPayload.match_id,
    admission_token: verification.response.admission_token,
  }));
  return await response;
}

async function reportGameEnded(startPayload, roomCode, result, token = GAME_SERVER_TOKEN) {
  const ws = await openSocket();
  const response = waitForMessage(ws, (message) =>
    message.type === "game_server_ended_ok" || message.type === "error"
  );
  ws.send(JSON.stringify({
    type: "game_server_ended",
    server_token: token,
    game_id: startPayload.game_id,
    match_id: startPayload.match_id,
    room_code: roomCode,
    result,
  }));
  const payload = await response;
  await closeClient(ws);
  return payload;
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
      PARDEX_GAME_SERVER_TOKEN: GAME_SERVER_TOKEN,
      PARDEX_SOCIAL_DATA_PATH: path.join(tempDir, "social.json"),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));

  let host;
  let joiner;
  let outsider;
  const gameSockets = [];
  try {
    await waitForServerReady(server);
    const health = await fetch(HEALTH_URL).then((response) => response.json());
    assert.strictEqual(health.roomLifecycle, true);
    assert.strictEqual(health.secureGameHandoff, true);
    const controlHealth = await fetch(CONTROL_HEALTH_URL).then((response) => response.json());
    assert.strictEqual(controlHealth.twoPhaseGameHandoff, true);
    assert.strictEqual(controlHealth.authoritativeGameEnd, true);
    assert.strictEqual(controlHealth.gameServerTokenConfigured, true);

    host = await connectClient("Lifecycle-Host");
    joiner = await connectClient("Lifecycle-Joiner");
    outsider = await connectClient("Lifecycle-Outsider");

    const createdPromise = waitForMessage(host.ws, (message) =>
      message.type === "room_state" && message.room?.members?.length === 1
    );
    host.ws.send(JSON.stringify({ type: "create_room", game_id: "korsanlar", max_players: 4 }));
    const created = await createdPromise;
    const roomCode = created.room.code;

    const hostSeesJoin = waitForMessage(host.ws, (message) =>
      message.type === "room_state" && message.room?.members?.length === 2
    );
    const joinerJoined = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state" && message.room?.code === roomCode && message.room?.members?.length === 2
    );
    joiner.ws.send(JSON.stringify({ type: "join_room", code: roomCode }));
    await Promise.all([hostSeesJoin, joinerJoined]);

    const first = await startMatch(host, joiner);

    const oldHelloWs = await openSocket();
    gameSockets.push(oldHelloWs);
    const oldHelloRejected = waitForMessage(oldHelloWs, (message) =>
      message.type === "error" && message.code === "GAME_TWO_PHASE_REQUIRED"
    );
    oldHelloWs.send(JSON.stringify({
      type: "game_hello",
      game_id: first.hostPayload.game_id,
      match_id: first.matchId,
      launch_ticket: first.hostPayload.launch_ticket,
    }));
    await oldHelloRejected;

    const wrongTicket = await verifyTicket(first.hostPayload, crypto.randomBytes(32).toString("base64url"));
    gameSockets.push(wrongTicket.ws);
    assert.strictEqual(wrongTicket.response.code, "GAME_TICKET_INVALID");

    const hostVerification = await verifyTicket(first.hostPayload);
    gameSockets.push(hostVerification.ws);
    assert.strictEqual(hostVerification.response.type, "game_ticket_ok");
    assert.strictEqual(hostVerification.response.user_id, host.userId);

    // Phase 1 must not mark the PARDEX member in_game yet.
    const reuseAfterVerify = await verifyTicket(first.hostPayload);
    gameSockets.push(reuseAfterVerify.ws);
    assert.strictEqual(reuseAfterVerify.response.code, "GAME_TICKET_INVALID");

    const hostConnectedSeen = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state"
      && message.room?.state === "launching"
      && message.room.members.find((member) => member.user_id === host.userId)?.game_state === "in_game"
      && message.room.members.find((member) => member.user_id === joiner.userId)?.game_state === "launching"
    );
    const hostAdmitted = await admitGame(hostVerification, first.hostPayload);
    assert.strictEqual(hostAdmitted.type, "game_admitted_ok");
    await hostConnectedSeen;

    const joinerVerification = await verifyTicket(first.joinerPayload);
    gameSockets.push(joinerVerification.ws);
    const hostGameStarted = waitForMessage(host.ws, (message) =>
      message.type === "game_started" && message.match_id === first.matchId
    );
    const joinerInGameState = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state" && message.room?.state === "in_game"
    );
    const joinerAdmitted = await admitGame(joinerVerification, first.joinerPayload);
    assert.strictEqual(joinerAdmitted.type, "game_admitted_ok");
    const [, inGameState] = await Promise.all([hostGameStarted, joinerInGameState]);
    assert.ok(inGameState.room.members.every((member) => member.game_state === "in_game"));

    const badServerEnd = await reportGameEnded(
      first.hostPayload,
      roomCode,
      { reason: "forged" },
      "wrong-game-server-token"
    );
    assert.strictEqual(badServerEnd.code, "GAME_SERVER_UNAUTHORIZED");

    const hostEnded = waitForMessage(host.ws, (message) =>
      message.type === "game_ended" && message.match_id === first.matchId && message.source === "game_server"
    );
    const joinerEndedState = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state" && message.room?.state === "ended"
    );
    const authoritativeResult = {
      reason: "victory",
      winner_user_id: host.userId,
      winner_name: "Lifecycle-Host",
      winner_fame: 30,
    };
    const serverEndAck = await reportGameEnded(first.hostPayload, roomCode, authoritativeResult);
    assert.strictEqual(serverEndAck.type, "game_server_ended_ok");
    const [endedEvent, endedState] = await Promise.all([hostEnded, joinerEndedState]);
    assert.strictEqual(endedEvent.result.winner_user_id, host.userId);
    assert.strictEqual(endedState.room.ended, true);
    assert.ok(endedState.room.members.every((member) => member.game_state === "ended"));

    const duplicateEndAck = await reportGameEnded(first.hostPayload, roomCode, authoritativeResult);
    assert.strictEqual(duplicateEndAck.type, "game_server_ended_ok");
    assert.strictEqual(duplicateEndAck.duplicate, true);

    const returnedToLobby = waitForMessage(joiner.ws, (message) =>
      message.type === "room_state" && message.room?.state === "lobby" && message.room?.match_id === ""
    );
    host.ws.send(JSON.stringify({ type: "return_to_lobby" }));
    await returnedToLobby;

    const second = await startMatch(host, joiner);
    const hostAbort = waitForMessage(host.ws, (message) =>
      message.type === "game_launch_aborted" && message.reason === "simulated_launch_failure"
    );
    joiner.ws.send(JSON.stringify({
      type: "launch_failed",
      match_id: second.matchId,
      reason: "simulated_launch_failure",
    }));
    await hostAbort;

    const finalHealth = await fetch(HEALTH_URL).then((response) => response.json());
    assert.strictEqual(finalHealth.pendingGameLaunchTickets, 0);
    assert.strictEqual(finalHealth.roomLifecycleCounts.lobby, 1);
    console.log("PARDEX lifecycle smoke test passed: two-phase admission -> in_game -> authoritative end -> lobby + rollback");
  } finally {
    for (const ws of gameSockets) await closeClient(ws);
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
