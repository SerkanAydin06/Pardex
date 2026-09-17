const assert = require("assert");
const { spawn } = require("child_process");
const path = require("path");
const WebSocket = require("ws");

const PORT = 9876;
const URL = `ws://127.0.0.1:${PORT}`;

function waitForMessage(ws, predicate, timeoutMs = 4000) {
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

async function connectClient(displayName) {
  const ws = new WebSocket(URL);
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });

  const welcomePromise = waitForMessage(ws, (message) => message.type === "welcome");
  ws.send(JSON.stringify({ type: "hello", display_name: displayName }));
  const welcome = await welcomePromise;
  assert.ok(welcome.user_id, "welcome must include user_id");
  assert.strictEqual(welcome.display_name, displayName);
  return { ws, userId: welcome.user_id };
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

async function main() {
  const server = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(PORT) },
    stdio: ["ignore", "pipe", "pipe"],
  });

  server.stderr.on("data", (chunk) => process.stderr.write(chunk));

  let first;
  let second;
  try {
    await waitForServerReady(server);
    first = await connectClient("Pardus-A");
    second = await connectClient("Pardus-B");

    const createdPromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state" && message.room?.members?.length === 1
    );
    first.ws.send(JSON.stringify({
      type: "create_room",
      game_id: "korsanlar",
      max_players: 4,
    }));
    const created = await createdPromise;
    const roomCode = created.room.code;
    assert.match(roomCode, /^[A-Z2-9]{5}$/);
    assert.strictEqual(created.room.host_id, first.userId);

    const firstJoinPromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state" && message.room?.members?.length === 2
    );
    const secondJoinPromise = waitForMessage(
      second.ws,
      (message) => message.type === "room_state" && message.room?.members?.length === 2
    );
    second.ws.send(JSON.stringify({ type: "join_room", code: roomCode }));
    const [firstJoined, secondJoined] = await Promise.all([firstJoinPromise, secondJoinPromise]);
    assert.strictEqual(firstJoined.room.code, roomCode);
    assert.strictEqual(secondJoined.room.code, roomCode);

    const firstReadyPromise = waitForMessage(
      first.ws,
      (message) => message.type === "room_state"
        && message.room?.members?.some((member) => member.user_id === second.userId && member.ready === true)
    );
    const secondReadyPromise = waitForMessage(
      second.ws,
      (message) => message.type === "room_state"
        && message.room?.members?.some((member) => member.user_id === second.userId && member.ready === true)
    );
    second.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
    await Promise.all([firstReadyPromise, secondReadyPromise]);

    console.log("PARDEX Online smoke test passed");
  } finally {
    if (first?.ws) first.ws.close();
    if (second?.ws) second.ws.close();
    server.kill("SIGTERM");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
