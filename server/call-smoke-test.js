const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9894;
const URL = `ws://127.0.0.1:${PORT}`;
const GAME_SERVER_URL = "ws://127.0.0.1:9999";
const GAME_SERVER_TOKEN = "pardex-quick-play-smoke-game-server-token-2026-xx";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-call:${value}`).digest("hex");
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
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-call-"));
  const server = spawn(process.execPath, ["production_server.js"], {
    cwd: __dirname,
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(PORT), PARDEX_SOCIAL_DATA_PATH: path.join(tempDir, "social.json"), CALL_RING_TIMEOUT_MS: "1500" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));
  const sockets = [];
  const callState = (ws, state) => waitForMessage(ws, (m) => m.type === "call_state" && m.call?.state === state);
  const ended = (ws, reason) => waitForMessage(ws, (m) => m.type === "call_ended" && m.reason === reason);
  try {
    await waitForServerReady(server);
    const ali = await connectClient("Call-Ali");
    const veli = await connectClient("Call-Veli");
    const yabanci = await connectClient("Call-Yabanci");
    sockets.push(ali.ws, veli.ws, yabanci.ws);
    await befriend(ali, veli);

    // Only friends can be called.
    const notFriends = waitForMessage(yabanci.ws, (m) => m.type === "error" && m.code === "NOT_FRIENDS");
    yabanci.ws.send(JSON.stringify({ type: "call_start", account_id: ali.accountId }));
    await notFriends;

    // Ring -> accept -> audio both ways -> mute -> hang up.
    const incoming = callState(veli.ws, "ringing");
    const outgoing = callState(ali.ws, "ringing");
    ali.ws.send(JSON.stringify({ type: "call_start", account_id: veli.accountId }));
    const [ring, out] = await Promise.all([incoming, outgoing]);
    assert.strictEqual(ring.call.outgoing, false);
    assert.strictEqual(ring.call.peer_name, "Call-Ali");
    assert.strictEqual(out.call.outgoing, true);
    // A third friend-less user cannot jump in; a busy callee is refused.
    const busy = waitForMessage(ali.ws, (m) => m.type === "error" && m.code === "CALL_BUSY");
    ali.ws.send(JSON.stringify({ type: "call_start", account_id: veli.accountId }));
    await busy;
    // Frames are not relayed before the call is accepted.
    let early = false;
    const earlyListener = (raw) => { if (JSON.parse(raw.toString("utf8")).type === "call_frame") early = true; };
    veli.ws.on("message", earlyListener);
    ali.ws.send(JSON.stringify({ type: "call_frame", seq: 1, data: "AAAA" }));
    await delay(200);
    veli.ws.off("message", earlyListener);
    assert.strictEqual(early, false, "no audio while ringing");
    const activeAli = callState(ali.ws, "active");
    const activeVeli = callState(veli.ws, "active");
    veli.ws.send(JSON.stringify({ type: "call_accept", call_id: ring.call.id }));
    await Promise.all([activeAli, activeVeli]);
    const frame = waitForMessage(veli.ws, (m) => m.type === "call_frame");
    ali.ws.send(JSON.stringify({ type: "call_frame", seq: 7, data: "QUJDRA==" }));
    assert.deepStrictEqual(await frame, { type: "call_frame", seq: 7, data: "QUJDRA==" });
    const back = waitForMessage(ali.ws, (m) => m.type === "call_frame");
    veli.ws.send(JSON.stringify({ type: "call_frame", seq: 1, data: "RUZHSA==" }));
    assert.strictEqual((await back).data, "RUZHSA==");
    const muted = waitForMessage(veli.ws, (m) => m.type === "call_peer_muted" && m.muted === true);
    ali.ws.send(JSON.stringify({ type: "call_mute", muted: true }));
    await muted;
    const hungAli = ended(ali.ws, "ended");
    const hungVeli = ended(veli.ws, "ended");
    veli.ws.send(JSON.stringify({ type: "call_end" }));
    await Promise.all([hungAli, hungVeli]);

    // Decline.
    const ring2 = callState(veli.ws, "ringing");
    ali.ws.send(JSON.stringify({ type: "call_start", account_id: veli.accountId }));
    const declined = ended(ali.ws, "declined");
    veli.ws.send(JSON.stringify({ type: "call_decline", call_id: (await ring2).call.id }));
    await declined;

    // Nobody answers: missed after the ring timeout.
    const ring3 = callState(veli.ws, "ringing");
    ali.ws.send(JSON.stringify({ type: "call_start", account_id: veli.accountId }));
    await ring3;
    await Promise.all([ended(ali.ws, "missed"), ended(veli.ws, "missed")]);

    // A dropped connection ends the call for the other side.
    const ring4 = callState(veli.ws, "ringing");
    ali.ws.send(JSON.stringify({ type: "call_start", account_id: veli.accountId }));
    const active4 = callState(ali.ws, "active");
    veli.ws.send(JSON.stringify({ type: "call_accept", call_id: (await ring4).call.id }));
    await active4;
    const dropped = ended(ali.ws, "disconnected");
    await closeSocket(veli.ws);
    await dropped;

    console.log("PARDEX call smoke passed: friends only + ring + busy + no audio before accept + audio both ways + mute + hang up + decline + missed + disconnect");
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
