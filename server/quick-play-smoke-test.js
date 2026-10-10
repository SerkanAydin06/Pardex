const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9889;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const GAME_SERVER_TOKEN = "pardex-quick-play-smoke-game-server-token-2026-xx";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-quick-play:${value}`).digest("hex");
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

async function befriend(first, second) {
  const incoming = waitForMessage(second.ws, (message) => message.type === "social_state"
    && message.state?.incoming_requests?.some((profile) => profile.account_id === first.accountId));
  first.ws.send(JSON.stringify({ type: "send_friend_request", account_id: second.accountId }));
  await incoming;
  const friends = waitForMessage(first.ws, (message) => message.type === "social_state"
    && message.state?.friends?.some((profile) => profile.account_id === second.accountId));
  second.ws.send(JSON.stringify({ type: "accept_friend_request", account_id: first.accountId }));
  await friends;
}

async function admitToGame(launch) {
  // What the Korsan dedicated server does with a launch ticket.
  const ws = await connectSocket();
  const ticketOk = waitForMessage(ws, (message) => message.type === "game_ticket_ok");
  ws.send(JSON.stringify({
    type: "game_ticket_verify",
    game_id: "korsanlar",
    match_id: launch.match_id,
    launch_ticket: launch.launch_ticket,
  }));
  const ok = await ticketOk;
  const admitted = waitForMessage(ws, (message) => message.type === "game_admitted_ok");
  ws.send(JSON.stringify({
    type: "game_admitted",
    game_id: "korsanlar",
    match_id: launch.match_id,
    admission_token: ok.admission_token,
  }));
  await admitted;
  await closeSocket(ws);
}

async function closeSocket(ws) {
  if (!ws || ws.readyState === WebSocket.CLOSED) return;
  const done = new Promise((resolve) => ws.once("close", resolve));
  ws.close();
  await done;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-quick-play-"));
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

  const clients = [];
  try {
    await waitForServerReady(server);
    const host = await connectClient("Quick-Host");
    const invited = await connectClient("Quick-Invited");
    const friend = await connectClient("Quick-Friend");
    const stranger = await connectClient("Quick-Stranger");
    const late = await connectClient("Quick-Late");
    clients.push(host, invited, friend, stranger, late);
    await befriend(host, invited);
    await befriend(host, friend);
    await befriend(host, late);

    // "Oyna" alone: a one-player match starts at once, no party or ready step.
    const hostStart = waitForMessage(host.ws, (message) => message.type === "game_start");
    host.ws.send(JSON.stringify({ type: "play_game", game_id: "korsanlar" }));
    const launch = await hostStart;
    assert.strictEqual(launch.room.quick_play, true);
    assert.strictEqual(launch.room.members.length, 1);
    assert.ok(launch.launch_ticket, "solo play must get a launch ticket");
    const code = launch.room.code;

    const inGame = waitForMessage(host.ws, (message) =>
      message.type === "room_state" && message.room?.code === code && message.room?.state === "in_game"
    );
    await admitToGame(launch);
    await inGame;

    // While the in-game lobby is open, friends can be invited into it.
    const invite = waitForMessage(invited.ws, (message) => message.type === "room_invite");
    host.ws.send(JSON.stringify({ type: "send_room_invite", account_id: invited.accountId }));
    const invitePayload = await invite;
    const invitedStart = waitForMessage(invited.ws, (message) => message.type === "game_start");
    invited.ws.send(JSON.stringify({ type: "accept_room_invite", invite_id: invitePayload.invite.id }));
    const invitedLaunch = await invitedStart;
    assert.strictEqual(invitedLaunch.match_id, launch.match_id, "invited player joins the running match");
    await admitToGame(invitedLaunch);

    // A stranger pressing "Oyna" cannot take the single Korsan server.
    const busy = waitForMessage(stranger.ws, (message) => message.type === "error" && message.code === "GAME_SERVER_BUSY");
    stranger.ws.send(JSON.stringify({ type: "play_game", game_id: "korsanlar" }));
    await busy;

    // A friend pressing "Oyna" lands in the open lobby with their friends.
    const friendStart = waitForMessage(friend.ws, (message) => message.type === "game_start");
    friend.ws.send(JSON.stringify({ type: "play_game", game_id: "korsanlar" }));
    const friendLaunch = await friendStart;
    assert.strictEqual(friendLaunch.room.code, code);
    assert.strictEqual(friendLaunch.match_id, launch.match_id);

    // If that friend's game cannot open, only they leave the match.
    const friendLeft = waitForMessage(friend.ws, (message) => message.type === "left_room");
    const hostSeesTwo = waitForMessage(host.ws, (message) =>
      message.type === "room_state" && message.room?.code === code
      && message.room?.members?.length === 2 && message.room?.state === "in_game"
    );
    friend.ws.send(JSON.stringify({ type: "launch_failed", match_id: launch.match_id }));
    await Promise.all([friendLeft, hostSeesTwo]);

    // Once the game server reports the match started, nobody else joins.
    const gameServer = await connectSocket();
    const startedAck = waitForMessage(gameServer, (message) => message.type === "game_server_started_ok");
    const hostSeesStarted = waitForMessage(host.ws, (message) =>
      message.type === "room_state" && message.room?.code === code && message.room?.match_started === true
    );
    gameServer.send(JSON.stringify({
      type: "game_server_started",
      server_token: GAME_SERVER_TOKEN,
      game_id: "korsanlar",
      match_id: launch.match_id,
      room_code: code,
    }));
    await Promise.all([startedAck, hostSeesStarted]);
    await closeSocket(gameServer);

    // A player whose game closed mid-match gets a ticket back into it.
    const rejoinStart = waitForMessage(invited.ws, (message) => message.type === "game_start");
    invited.ws.send(JSON.stringify({ type: "play_game", game_id: "korsanlar" }));
    const rejoin = await rejoinStart;
    assert.strictEqual(rejoin.match_id, launch.match_id, "rejoin uses the running match");
    assert.ok(rejoin.launch_ticket);

    const lateBusy = waitForMessage(late.ws, (message) => message.type === "error" && message.code === "GAME_SERVER_BUSY");
    late.ws.send(JSON.stringify({ type: "play_game", game_id: "korsanlar" }));
    await lateBusy;
    const lateJoinRejected = waitForMessage(late.ws, (message) => message.type === "error" && message.code === "ROOM_IN_GAME");
    late.ws.send(JSON.stringify({ type: "join_friend_room", account_id: host.accountId }));
    await lateJoinRejected;

    // When everyone closes the game the room disappears and the server frees up.
    host.ws.send(JSON.stringify({ type: "leave_room" }));
    invited.ws.send(JSON.stringify({ type: "leave_room" }));
    await waitForMessage(invited.ws, (message) => message.type === "left_room");
    const freshStart = waitForMessage(stranger.ws, (message) => message.type === "game_start");
    stranger.ws.send(JSON.stringify({ type: "play_game", game_id: "korsanlar" }));
    const fresh = await freshStart;
    assert.notStrictEqual(fresh.match_id, launch.match_id);

    console.log("PARDEX quick play smoke passed: solo start + invite into running lobby + friend auto-join + busy guard + launch failure + match started lock + rejoin + release");
  } finally {
    for (const client of clients) await closeSocket(client.ws);
    server.kill();
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
