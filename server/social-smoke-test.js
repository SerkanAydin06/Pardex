const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9877;
const URL = `ws://127.0.0.1:${PORT}`;

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-social-smoke:${value}`).digest("hex");
}

function waitForMessage(ws, predicate, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.off("message", onMessage);
      reject(new Error("Timed out waiting for social WebSocket message"));
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
    const timeout = setTimeout(() => reject(new Error("Social server startup timeout")), 5000);
    server.stdout.on("data", (chunk) => {
      if (!chunk.toString("utf8").includes("PARDEX Online listening")) return;
      clearTimeout(timeout);
      resolve();
    });
    server.once("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`Social server exited before ready with code ${code}`));
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
      SESSION_GRACE_MS: "1000",
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

async function connectClient(displayName, identityKey) {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });

  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  ws.send(JSON.stringify({
    type: "hello",
    display_name: displayName,
    identity_key: identityKey,
  }));
  const welcome = await welcomePromise;
  assert.ok(welcome.account_id, "social welcome must include account_id");
  assert.strictEqual(welcome.social_enabled, true);
  return {
    ws,
    accountId: welcome.account_id,
    identityKey,
    displayName,
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

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-social-smoke-"));
  const socialDataPath = path.join(tempDir, "social.json");
  const firstIdentity = identityKeyFor("Pardus-A");
  const secondIdentity = identityKeyFor("Pardus-B");

  let server;
  let first;
  let second;
  try {
    server = await startServer(socialDataPath);
    first = await connectClient("Pardus-A", firstIdentity);
    second = await connectClient("Pardus-B", secondIdentity);
    assert.notStrictEqual(first.accountId, second.accountId);

    const searchPromise = waitForMessage(
      first.ws,
      (message) => message.type === "user_search_results"
        && message.results?.some((profile) => profile.account_id === second.accountId)
    );
    first.ws.send(JSON.stringify({ type: "search_users", query: "Pardus-B" }));
    const search = await searchPromise;
    const found = search.results.find((profile) => profile.account_id === second.accountId);
    assert.strictEqual(found.relationship, "none");
    assert.strictEqual(found.online, true);

    const firstOutgoingPromise = waitForMessage(
      first.ws,
      (message) => message.type === "social_state"
        && message.state?.outgoing_requests?.some((profile) => profile.account_id === second.accountId)
    );
    const secondIncomingPromise = waitForMessage(
      second.ws,
      (message) => message.type === "social_state"
        && message.state?.incoming_requests?.some((profile) => profile.account_id === first.accountId)
    );
    first.ws.send(JSON.stringify({
      type: "send_friend_request",
      account_id: second.accountId,
    }));
    await Promise.all([firstOutgoingPromise, secondIncomingPromise]);

    const firstFriendPromise = waitForMessage(
      first.ws,
      (message) => message.type === "social_state"
        && message.state?.friends?.some((profile) => profile.account_id === second.accountId)
    );
    const secondFriendPromise = waitForMessage(
      second.ws,
      (message) => message.type === "social_state"
        && message.state?.friends?.some((profile) => profile.account_id === first.accountId)
    );
    second.ws.send(JSON.stringify({
      type: "accept_friend_request",
      account_id: first.accountId,
    }));
    await Promise.all([firstFriendPromise, secondFriendPromise]);

    // Profile picture: friends see an avatar_id and fetch the image once.
    const avatarData = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 7)]).toString("base64");
    const invalidAvatarPromise = waitForMessage(first.ws, (message) => message.type === "error" && message.code === "AVATAR_INVALID");
    first.ws.send(JSON.stringify({ type: "set_avatar", data: Buffer.from("not an image").toString("base64") }));
    await invalidAvatarPromise;
    const secondSeesAvatarPromise = waitForMessage(
      second.ws,
      (message) => message.type === "social_state"
        && message.state?.friends?.some((profile) => profile.account_id === first.accountId && profile.avatar_id)
    );
    first.ws.send(JSON.stringify({ type: "set_avatar", data: avatarData }));
    const avatarState = await secondSeesAvatarPromise;
    const avatarId = avatarState.state.friends.find((profile) => profile.account_id === first.accountId).avatar_id;
    const avatarReplyPromise = waitForMessage(second.ws, (message) => message.type === "avatar_data");
    second.ws.send(JSON.stringify({ type: "get_avatar", account_id: first.accountId }));
    const avatarReply = await avatarReplyPromise;
    assert.strictEqual(avatarReply.account_id, first.accountId);
    assert.strictEqual(avatarReply.avatar_id, avatarId);
    assert.strictEqual(avatarReply.data, avatarData);

    const originalFirstAccountId = first.accountId;
    const originalSecondAccountId = second.accountId;
    await closeClient(first);
    await closeClient(second);
    first = null;
    second = null;
    await stopServer(server);
    server = null;

    assert.ok(fs.existsSync(socialDataPath), "social data must be persisted to disk");

    server = await startServer(socialDataPath);
    first = await connectClient("Pardus-A", firstIdentity);
    second = await connectClient("Pardus-B", secondIdentity);
    assert.strictEqual(first.accountId, originalFirstAccountId, "account id must survive server restart");
    assert.strictEqual(second.accountId, originalSecondAccountId, "second account id must survive restart");

    const [firstState, secondState] = await Promise.all([
      requestSocialState(first),
      requestSocialState(second),
    ]);
    assert.ok(firstState.friends.some((profile) => profile.account_id === second.accountId));
    assert.ok(secondState.friends.some((profile) => profile.account_id === first.accountId));
    assert.ok(firstState.self.avatar_id, "profile picture must survive server restart");

    const firstRemovedPromise = waitForMessage(
      first.ws,
      (message) => message.type === "social_state" && message.state?.friends?.length === 0
    );
    const secondRemovedPromise = waitForMessage(
      second.ws,
      (message) => message.type === "social_state" && message.state?.friends?.length === 0
    );
    first.ws.send(JSON.stringify({ type: "remove_friend", account_id: second.accountId }));
    await Promise.all([firstRemovedPromise, secondRemovedPromise]);

    console.log(
      "PARDEX social smoke test passed: stable identity -> search -> request -> accept -> avatar -> persistence -> remove"
    );
  } finally {
    await closeClient(first);
    await closeClient(second);
    await stopServer(server);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
