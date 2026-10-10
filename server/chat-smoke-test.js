const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9891;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const GAME_SERVER_TOKEN = "pardex-quick-play-smoke-game-server-token-2026-xx";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-chat:${value}`).digest("hex");
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

async function closeSocket(ws) {
  if (!ws || ws.readyState === WebSocket.CLOSED) return;
  const done = new Promise((resolve) => ws.once("close", resolve));
  ws.close();
  await done;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-chat-"));
  const dataPath = path.join(tempDir, "social.json");
  const start = () => {
    const server = spawn(process.execPath, ["production_server.js"], {
      cwd: __dirname,
      env: { ...process.env, HOST: "127.0.0.1", PORT: String(PORT), PARDEX_SOCIAL_DATA_PATH: dataPath },
      stdio: ["ignore", "pipe", "pipe"],
    });
    server.stderr.on("data", (chunk) => process.stderr.write(chunk));
    return server;
  };
  let server = start();
  const sockets = [];
  try {
    await waitForServerReady(server);
    const ali = await connectClient("Chat-Ali");
    const veli = await connectClient("Chat-Veli");
    const yabanci = await connectClient("Chat-Yabanci");
    sockets.push(ali.ws, veli.ws, yabanci.ws);

    // Strangers cannot message each other.
    const denied = waitForMessage(yabanci.ws, (m) => m.type === "error" && m.code === "NOT_FRIENDS");
    yabanci.ws.send(JSON.stringify({ type: "send_chat", account_id: ali.accountId, text: "selam" }));
    await denied;

    await befriend(ali, veli);
    const echo = waitForMessage(ali.ws, (m) => m.type === "chat_message" && m.client_id === "c1");
    const delivered = waitForMessage(veli.ws, (m) => m.type === "chat_message" && m.with === ali.accountId);
    const unread = waitForMessage(veli.ws, (m) => m.type === "social_state"
      && m.state?.friends?.some((f) => f.account_id === ali.accountId && f.chat_unread === 1 && f.chat_last_text === "Selam Veli!"));
    ali.ws.send(JSON.stringify({ type: "send_chat", account_id: veli.accountId, text: "  Selam Veli!\u0007 ", client_id: "c1" }));
    const [mine, theirs] = await Promise.all([echo, delivered, unread]);
    assert.strictEqual(theirs.message.text, "Selam Veli!", "control characters and spaces are stripped");
    assert.strictEqual(mine.message.id, theirs.message.id);

    const read = waitForMessage(veli.ws, (m) => m.type === "social_state"
      && m.state?.friends?.some((f) => f.account_id === ali.accountId && f.chat_unread === 0));
    veli.ws.send(JSON.stringify({ type: "mark_chat_read", account_id: ali.accountId }));
    await read;

    const empty = waitForMessage(veli.ws, (m) => m.type === "error" && m.code === "EMPTY_MESSAGE");
    veli.ws.send(JSON.stringify({ type: "send_chat", account_id: ali.accountId, text: "   " }));
    await empty;

    // Spam is limited.
    const limited = waitForMessage(veli.ws, (m) => m.type === "error" && m.code === "CHAT_RATE_LIMIT");
    for (let i = 0; i < 13; i += 1) veli.ws.send(JSON.stringify({ type: "send_chat", account_id: ali.accountId, text: `m${i}` }));
    await limited;

    // History survives a server restart.
    for (const ws of sockets.splice(0)) await closeSocket(ws);
    server.kill();
    await new Promise((resolve) => server.once("exit", resolve));
    server = start();
    await waitForServerReady(server);
    const again = await connectClient("Chat-Ali");
    sockets.push(again.ws);
    const history = waitForMessage(again.ws, (m) => m.type === "chat_history");
    again.ws.send(JSON.stringify({ type: "get_chat_history", account_id: veli.accountId }));
    const { messages } = await history;
    assert.strictEqual(messages[0].text, "Selam Veli!");
    assert.ok(messages.length >= 12, `history keeps the conversation (${messages.length})`);

    console.log("PARDEX chat smoke passed: friends only + delivery + unread/read + empty + rate limit + persisted history");
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
