const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9882;
const URL = `ws://127.0.0.1:${PORT}`;
const RECOVERY_CODE = "PX1-1111-2222-3333-4444-5555-6666-7777-8888";
const ROTATED_RECOVERY_CODE = "PX1-AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-0000-9999";

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-recovery-smoke:${value}`).digest("hex");
}

function waitForMessage(ws, predicate, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.off("message", onMessage);
      reject(new Error("Timed out waiting for recovery WebSocket message"));
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
    const timeout = setTimeout(() => reject(new Error("Recovery server startup timeout")), 5000);
    server.stdout.on("data", (chunk) => {
      if (!chunk.toString("utf8").includes("PARDEX Online listening")) return;
      clearTimeout(timeout);
      resolve();
    });
    server.once("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`Recovery server exited before ready with code ${code}`));
    });
  });
}

async function startServer(socialDataPath) {
  const server = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      SESSION_GRACE_MS: "750",
      PARDEX_SOCIAL_DATA_PATH: socialDataPath,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));
  await waitForServerReady(server);
  return server;
}

async function stopServer(server) {
  if (!server || server.exitCode !== null) return;
  const exited = new Promise((resolve) => server.once("exit", resolve));
  server.kill("SIGTERM");
  await exited;
}

async function openSocket() {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
  return ws;
}

async function connectClient(displayName, identityKey, recoveryCode = "") {
  const ws = await openSocket();
  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  const hello = {
    type: "hello",
    display_name: displayName,
    identity_key: identityKey,
  };
  if (recoveryCode) hello.recovery_code = recoveryCode;
  ws.send(JSON.stringify(hello));
  const welcome = await welcomePromise;
  return {
    ws,
    accountId: welcome.account_id,
    displayName: welcome.display_name,
    recovered: Boolean(welcome.recovered),
    recoveryEnabled: Boolean(welcome.recovery_enabled),
  };
}

async function requestSocialState(client) {
  const statePromise = waitForMessage(client.ws, (message) => message.type === "social_state");
  client.ws.send(JSON.stringify({ type: "get_social_state" }));
  return (await statePromise).state;
}

async function closeClient(client) {
  if (!client?.ws || client.ws.readyState === WebSocket.CLOSED) return;
  const closed = new Promise((resolve) => client.ws.once("close", resolve));
  client.ws.close();
  await closed;
}

async function rejectUsedRecoveryCode(identityKey) {
  const ws = await openSocket();
  const errorPromise = waitForMessage(
    ws,
    (message) => message.type === "error" && message.code === "INVALID_RECOVERY_CODE"
  );
  ws.send(JSON.stringify({
    type: "hello",
    display_name: "Recovery-Replay",
    identity_key: identityKey,
    recovery_code: RECOVERY_CODE,
  }));
  const error = await errorPromise;
  assert.match(error.message, /geçersiz|kullanılmış/i);
  ws.close();
}

async function rejectRevokedIdentity(identityKey) {
  const ws = await openSocket();
  const errorPromise = waitForMessage(
    ws,
    (message) => message.type === "error" && message.code === "INVALID_IDENTITY"
  );
  ws.send(JSON.stringify({
    type: "hello",
    display_name: "Old-Device",
    identity_key: identityKey,
  }));
  const error = await errorPromise;
  assert.match(error.message, /taşındı|geçersiz/i);
  ws.close();
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-recovery-smoke-"));
  const socialDataPath = path.join(tempDir, "social.json");
  const originalIdentity = identityKeyFor("original-device");
  const friendIdentity = identityKeyFor("friend-device");
  const recoveredIdentity = identityKeyFor("replacement-device");
  const replayIdentity = identityKeyFor("replay-device");

  let server;
  let original;
  let friend;
  let recovered;
  let reconnected;
  try {
    server = await startServer(socialDataPath);
    original = await connectClient("Pardus-A", originalIdentity);
    friend = await connectClient("Pardus-B", friendIdentity);

    const friendIncoming = waitForMessage(
      friend.ws,
      (message) => message.type === "social_state"
        && message.state?.incoming_requests?.some((profile) => profile.account_id === original.accountId)
    );
    original.ws.send(JSON.stringify({
      type: "send_friend_request",
      account_id: friend.accountId,
    }));
    await friendIncoming;

    const originalFriend = waitForMessage(
      original.ws,
      (message) => message.type === "social_state"
        && message.state?.friends?.some((profile) => profile.account_id === friend.accountId)
    );
    friend.ws.send(JSON.stringify({
      type: "accept_friend_request",
      account_id: original.accountId,
    }));
    await originalFriend;

    const recoverySaved = waitForMessage(
      original.ws,
      (message) => message.type === "recovery_code_saved" && message.recovery_enabled === true
    );
    original.ws.send(JSON.stringify({
      type: "set_recovery_code",
      recovery_code: RECOVERY_CODE,
    }));
    await recoverySaved;

    const originalAccountId = original.accountId;
    const oldSessionClosed = new Promise((resolve) => {
      original.ws.once("close", (code) => resolve(code));
    });

    recovered = await connectClient("Yeni-Cihaz-Adi", recoveredIdentity, RECOVERY_CODE);
    assert.strictEqual(await oldSessionClosed, 4003, "recovery must immediately terminate the previous device session");
    original = null;

    assert.strictEqual(recovered.accountId, originalAccountId, "recovery must restore the original account id");
    assert.strictEqual(recovered.displayName, "Pardus-A", "recovery must preserve the original display name");
    assert.strictEqual(recovered.recovered, true, "welcome must identify a recovery handshake");
    assert.strictEqual(recovered.recoveryEnabled, false, "one-time recovery code must be invalidated after use");

    const recoveredState = await requestSocialState(recovered);
    assert.ok(
      recoveredState.friends.some((profile) => profile.account_id === friend.accountId),
      "friend relationships must survive account recovery"
    );

    await rejectUsedRecoveryCode(replayIdentity);

    const rotatedSaved = waitForMessage(
      recovered.ws,
      (message) => message.type === "recovery_code_saved" && message.recovery_enabled === true
    );
    recovered.ws.send(JSON.stringify({
      type: "set_recovery_code",
      recovery_code: ROTATED_RECOVERY_CODE,
    }));
    await rotatedSaved;

    await closeClient(recovered);
    recovered = null;
    await closeClient(friend);
    friend = null;
    await stopServer(server);
    server = null;

    const persisted = fs.readFileSync(socialDataPath, "utf8");
    assert.ok(!persisted.includes(RECOVERY_CODE), "plain recovery code must never be persisted");
    assert.ok(!persisted.includes(ROTATED_RECOVERY_CODE), "rotated recovery code must never be persisted");
    assert.ok(!persisted.includes(originalIdentity), "raw device identity must never be persisted");
    assert.ok(!persisted.includes(recoveredIdentity), "recovered raw device identity must never be persisted");
    const parsed = JSON.parse(persisted);
    assert.strictEqual(parsed.version, 2, "social store must migrate to version 2");
    assert.ok(Object.keys(parsed.identity_aliases || {}).length >= 2, "identity aliases must persist hashed device bindings");

    server = await startServer(socialDataPath);
    await rejectRevokedIdentity(originalIdentity);
    reconnected = await connectClient("Pardus-A", recoveredIdentity);
    assert.strictEqual(
      reconnected.accountId,
      originalAccountId,
      "recovered device identity must resolve to the original account after server restart"
    );

    console.log(
      "PARDEX recovery smoke test passed: friendship -> one-time transfer -> old-session revocation -> persistence"
    );
  } finally {
    await closeClient(original);
    await closeClient(friend);
    await closeClient(recovered);
    await closeClient(reconnected);
    await stopServer(server);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
