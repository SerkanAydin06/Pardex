const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9890;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const GAME_SERVER_TOKEN = "pardex-game-link-smoke-game-server-token-2026-xxxx";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-game-link:${value}`).digest("hex");
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

async function linkGame(owner) {
  const sessionMessage = waitForMessage(owner.ws, (message) => message.type === "game_session");
  owner.ws.send(JSON.stringify({ type: "get_game_session", game_id: "korsanlar" }));
  const { token } = await sessionMessage;
  const ws = await connectSocket();
  const ok = waitForMessage(ws, (message) => message.type === "game_link_ok");
  ws.send(JSON.stringify({ type: "game_link", token }));
  const linked = await ok;
  assert.strictEqual(linked.user_id, owner.userId);
  return ws;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-game-link-"));
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

  const sockets = [];
  try {
    await waitForServerReady(server);
    const host = await connectClient("Link-Host");
    const friend = await connectClient("Link-Friend");
    const stranger = await connectClient("Link-Stranger");
    sockets.push(host.ws, friend.ws, stranger.ws);
    await befriend(host, friend);

    // A forged token never links.
    const bogus = await connectSocket();
    sockets.push(bogus);
    const rejected = waitForMessage(bogus, (message) => message.type === "error" && message.code === "GAME_SESSION_INVALID");
    bogus.send(JSON.stringify({ type: "game_link", token: "not-a-token" }));
    await rejected;

    // The game PARDEX opened hosts a table itself; the ticket goes to the game.
    const hostGame = await linkGame(host);
    sockets.push(hostGame);
    let pardexGotStart = false;
    host.ws.on("message", (raw) => { if (JSON.parse(raw).type === "game_start") pardexGotStart = true; });
    const hostTicket = waitForMessage(hostGame, (message) => message.type === "match_ticket");
    hostGame.send(JSON.stringify({ type: "host_match" }));
    const hosted = await hostTicket;
    assert.ok(hosted.launch_ticket && hosted.room.code && hosted.role === "host");
    const code = hosted.room.code;
    await admitToGame(hosted);

    // Anyone with the code joins from their own game.
    const strangerGame = await linkGame(stranger);
    sockets.push(strangerGame);
    const missing = waitForMessage(strangerGame, (message) => message.type === "error" && message.code === "ROOM_NOT_FOUND");
    strangerGame.send(JSON.stringify({ type: "join_match", code: "ZZZZZ" }));
    await missing;
    const strangerTicket = waitForMessage(strangerGame, (message) => message.type === "match_ticket");
    strangerGame.send(JSON.stringify({ type: "join_match", code: code.toLowerCase() }));
    const joined = await strangerTicket;
    assert.strictEqual(joined.match_id, hosted.match_id);
    assert.strictEqual(joined.role, "client");

    // A friend whose game is closed presses "Katıl" in PARDEX: PARDEX gets
    // game_start and launches the game straight into the table.
    const friendStart = waitForMessage(friend.ws, (message) => message.type === "game_start");
    friend.ws.send(JSON.stringify({ type: "join_friend_room", account_id: host.accountId }));
    const friendLaunch = await friendStart;
    assert.strictEqual(friendLaunch.match_id, hosted.match_id);
    assert.strictEqual(pardexGotStart, false, "host's PARDEX must not relaunch an open game");

    console.log("PARDEX game link smoke passed: token link + forged token rejected + host from game + join by code + friend join via PARDEX");
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
