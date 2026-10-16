const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9892;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const GAME_SERVER_TOKEN = "pardex-quick-play-smoke-game-server-token-2026-xx";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-block:${value}`).digest("hex");
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

function getJson(url, token) {
  const http = require("http");
  return new Promise((resolve, reject) => {
    http.get(url, { headers: { Authorization: `Bearer ${token}` } }, (res) => {
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => resolve({ status: res.statusCode, body: JSON.parse(data || "{}") }));
    }).on("error", reject);
  });
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-block-"));
  const dataPath = path.join(tempDir, "social.json");
  const adminToken = "block-smoke-admin-token";
  const server = spawn(process.execPath, ["production_server.js"], {
    cwd: __dirname,
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(PORT), PARDEX_SOCIAL_DATA_PATH: dataPath, PARDEX_ADMIN_TOKEN: adminToken },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));
  const sockets = [];
  try {
    await waitForServerReady(server);
    const ali = await connectClient("Block-Ali");
    const veli = await connectClient("Block-Veli");
    sockets.push(ali.ws, veli.ws);
    await befriend(ali, veli);
    const got = waitForMessage(veli.ws, (m) => m.type === "chat_message");
    ali.ws.send(JSON.stringify({ type: "send_chat", account_id: veli.accountId, text: "kaba bir mesaj" }));
    await got;

    // Report keeps the recent conversation for the host.
    const reported = waitForMessage(veli.ws, (m) => m.type === "social_notice" && /iletildi/.test(m.message || ""));
    veli.ws.send(JSON.stringify({ type: "report_user", account_id: ali.accountId, reason: "Hakaret" }));
    await reported;
    const forbidden = await getJson(`http://127.0.0.1:${PORT}/admin/reports`, "wrong");
    assert.strictEqual(forbidden.status, 403);
    const reports = await getJson(`http://127.0.0.1:${PORT}/admin/reports`, adminToken);
    assert.strictEqual(reports.body.reports.length, 1);
    assert.strictEqual(reports.body.reports[0].reason, "Hakaret");
    assert.strictEqual(reports.body.reports[0].messages[0].text, "kaba bir mesaj");

    // Blocking ends the friendship both ways and stops messages/requests.
    const blockedState = waitForMessage(veli.ws, (m) => m.type === "social_state"
      && m.state?.blocked?.some((p) => p.account_id === ali.accountId) && !m.state?.friends?.length);
    const aliLost = waitForMessage(ali.ws, (m) => m.type === "social_state" && m.state?.friends?.length === 0);
    veli.ws.send(JSON.stringify({ type: "block_user", account_id: ali.accountId }));
    await Promise.all([blockedState, aliLost]);
    const noChat = waitForMessage(ali.ws, (m) => m.type === "error" && m.code === "NOT_FRIENDS");
    ali.ws.send(JSON.stringify({ type: "send_chat", account_id: veli.accountId, text: "tekrar" }));
    await noChat;
    const silent = waitForMessage(ali.ws, (m) => m.type === "social_notice" && m.code === "REQUEST_SENT");
    ali.ws.send(JSON.stringify({ type: "send_friend_request", account_id: veli.accountId }));
    await silent;
    const store = JSON.parse(fs.readFileSync(dataPath, "utf8"));
    assert.ok(!store.accounts[veli.accountId].incoming_requests.includes(ali.accountId), "blocked user's request never arrives");

    const unblocked = waitForMessage(veli.ws, (m) => m.type === "social_state" && m.state?.blocked?.length === 0);
    veli.ws.send(JSON.stringify({ type: "unblock_user", account_id: ali.accountId }));
    await unblocked;

    const day = new Date().toISOString().slice(0, 10);
    assert.ok(fs.existsSync(path.join(tempDir, "backups", `social-${day}.json`)), "daily backup is written");

    console.log("PARDEX block smoke passed: report + admin reports + block both ways + silent request + unblock + daily backup");
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
