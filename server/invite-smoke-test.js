const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const PORT = 9878;
const URL = `ws://127.0.0.1:${PORT}`;

function identityKeyFor(value) {
  return crypto.createHash("sha256").update(`pardex-invite-smoke:${value}`).digest("hex");
}

function waitForMessage(ws, predicate, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.off("message", onMessage);
      reject(new Error("Timed out waiting for room invite WebSocket message"));
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
    const timeout = setTimeout(() => reject(new Error("Invite server startup timeout")), 5000);
    server.stdout.on("data", (chunk) => {
      if (!chunk.toString("utf8").includes("PARDEX Online listening")) return;
      clearTimeout(timeout);
      resolve();
    });
    server.once("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`Invite server exited before ready with code ${code}`));
    });
  });
}

async function connectClient(displayName) {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  ws.send(JSON.stringify({
    type: "hello",
    display_name: displayName,
    identity_key: identityKeyFor(displayName),
  }));
  const welcome = await welcomePromise;
  return { ws, accountId: welcome.account_id, userId: welcome.user_id, displayName };
}

async function closeClient(client) {
  if (!client?.ws || client.ws.readyState === WebSocket.CLOSED) return;
  const closed = new Promise((resolve) => client.ws.once("close", resolve));
  client.ws.close();
  await closed;
}

async function makeFriends(first, second) {
  const incoming = waitForMessage(
    second.ws,
    (message) => message.type === "social_state"
      && message.state?.incoming_requests?.some((p) => p.account_id === first.accountId)
  );
  first.ws.send(JSON.stringify({ type: "send_friend_request", account_id: second.accountId }));
  await incoming;

  const firstFriend = waitForMessage(
    first.ws,
    (message) => message.type === "social_state"
      && message.state?.friends?.some((p) => p.account_id === second.accountId)
  );
  const secondFriend = waitForMessage(
    second.ws,
    (message) => message.type === "social_state"
      && message.state?.friends?.some((p) => p.account_id === first.accountId)
  );
  second.ws.send(JSON.stringify({ type: "accept_friend_request", account_id: first.accountId }));
  await Promise.all([firstFriend, secondFriend]);
}

async function createRoom(client) {
  const roomPromise = waitForMessage(
    client.ws,
    (message) => message.type === "room_state" && message.room?.members?.length === 1
  );
  client.ws.send(JSON.stringify({ type: "create_room", game_id: "korsanlar", max_players: 4 }));
  return (await roomPromise).room;
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-invite-smoke-"));
  const socialDataPath = path.join(tempDir, "social.json");
  const server = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      SESSION_GRACE_MS: "1000",
      ROOM_INVITE_TTL_MS: "15000",
      PARDEX_SOCIAL_DATA_PATH: socialDataPath,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));

  let first;
  let second;
  try {
    await waitForServerReady(server);
    first = await connectClient("Invite-A");
    second = await connectClient("Invite-B");
    await makeFriends(first, second);

    const room = await createRoom(first);
    assert.match(room.code, /^[A-Z2-9]{5}$/);

    const invitePromise = waitForMessage(second.ws, (message) => message.type === "room_invite");
    const sentNotice = waitForMessage(
      first.ws,
      (message) => message.type === "social_notice" && message.code === "ROOM_INVITE_SENT"
    );
    first.ws.send(JSON.stringify({ type: "send_room_invite", account_id: second.accountId }));
    const [inviteMessage] = await Promise.all([invitePromise, sentNotice]);
    const invite = inviteMessage.invite;
    assert.ok(invite.id);
    assert.strictEqual(invite.room_code, room.code);
    assert.strictEqual(invite.from_account_id, first.accountId);
    assert.strictEqual(invite.from_display_name, first.displayName);
    assert.strictEqual(invite.member_count, 1);
    assert.strictEqual(invite.max_players, 4);

    const closedAccepted = waitForMessage(
      second.ws,
      (message) => message.type === "room_invite_closed"
        && message.invite_id === invite.id
        && message.reason === "accepted"
    );
    const firstRoomTwo = waitForMessage(
      first.ws,
      (message) => message.type === "room_state"
        && message.room?.code === room.code
        && message.room.members.length === 2
    );
    const secondRoomTwo = waitForMessage(
      second.ws,
      (message) => message.type === "room_state"
        && message.room?.code === room.code
        && message.room.members.length === 2
    );
    second.ws.send(JSON.stringify({ type: "accept_room_invite", invite_id: invite.id }));
    const [, firstJoined, secondJoined] = await Promise.all([closedAccepted, firstRoomTwo, secondRoomTwo]);
    assert.ok(firstJoined.room.members.some((m) => m.account_id === second.accountId));
    assert.ok(secondJoined.room.members.some((m) => m.account_id === first.accountId));

    const leftPromise = waitForMessage(second.ws, (message) => message.type === "left_room");
    second.ws.send(JSON.stringify({ type: "leave_room" }));
    await leftPromise;

    const declineInvitePromise = waitForMessage(second.ws, (message) => message.type === "room_invite");
    first.ws.send(JSON.stringify({ type: "send_room_invite", account_id: second.accountId }));
    const declineInvite = (await declineInvitePromise).invite;
    const inviterDeclined = waitForMessage(
      first.ws,
      (message) => message.type === "social_notice" && message.code === "ROOM_INVITE_DECLINED"
    );
    second.ws.send(JSON.stringify({ type: "decline_room_invite", invite_id: declineInvite.id }));
    await inviterDeclined;

    await closeClient(second);
    const offlineError = waitForMessage(
      first.ws,
      (message) => message.type === "error" && message.code === "FRIEND_OFFLINE"
    );
    first.ws.send(JSON.stringify({ type: "send_room_invite", account_id: second.accountId }));
    await offlineError;

    console.log("PARDEX invite smoke test passed: friends -> invite -> accept/join -> decline -> offline guard");
  } finally {
    await closeClient(first);
    await closeClient(second);
    server.kill("SIGTERM");
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});