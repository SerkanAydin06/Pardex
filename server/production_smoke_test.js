// Live PARDEX room-to-game launch smoke test.
const WebSocket = require("ws");

const URL = process.env.PARDEX_ONLINE_URL || "wss://pardex-online-production.up.railway.app";
const EXPECTED_GAME_SERVER_URL = process.env.PARDEX_GAME_SERVER_URL || "wss://korsan-game-production.up.railway.app";
const TIMEOUT_MS = 15000;

function connect(name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL);
    const timer = setTimeout(() => reject(new Error(`Timeout connecting ${name}`)), TIMEOUT_MS);

    ws.on("open", () => {
      ws.send(JSON.stringify({ type: "hello", display_name: name }));
    });

    ws.on("message", (raw) => {
      const msg = JSON.parse(raw.toString("utf8"));
      if (msg.type === "welcome") {
        clearTimeout(timer);
        resolve({ ws, userId: msg.user_id });
      }
    });

    ws.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

function waitFor(ws, predicate, label) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`Timeout waiting for ${label}`));
    }, TIMEOUT_MS);

    const onMessage = (raw) => {
      const msg = JSON.parse(raw.toString("utf8"));
      if (predicate(msg)) {
        cleanup();
        resolve(msg);
      }
    };

    const onError = (err) => {
      cleanup();
      reject(err);
    };

    function cleanup() {
      clearTimeout(timer);
      ws.off("message", onMessage);
      ws.off("error", onError);
    }

    ws.on("message", onMessage);
    ws.on("error", onError);
  });
}

async function markReady(client, observer, userId, code) {
  const observerReady = waitFor(
    observer.ws,
    (msg) => msg.type === "room_state"
      && msg.room?.code === code
      && msg.room.members.some((m) => m.user_id === userId && m.ready === true),
    `ready sync for ${userId}`
  );
  client.ws.send(JSON.stringify({ type: "set_ready", ready: true }));
  await observerReady;
}

async function main() {
  const a = await connect("CI-A");
  const b = await connect("CI-B");

  try {
    const roomCreated = waitFor(
      a.ws,
      (msg) => msg.type === "room_state" && msg.room?.members?.length === 1,
      "room creation"
    );
    a.ws.send(JSON.stringify({ type: "create_room", game_id: "korsanlar", max_players: 4 }));
    const created = await roomCreated;
    const code = created.room.code;
    if (!code) throw new Error("Room code missing");
    if (created.room.game_server_url !== EXPECTED_GAME_SERVER_URL) {
      throw new Error(
        `Game server assignment mismatch: expected ${EXPECTED_GAME_SERVER_URL}, got ${created.room.game_server_url || "<empty>"}`
      );
    }

    const aSeesTwo = waitFor(
      a.ws,
      (msg) => msg.type === "room_state" && msg.room?.code === code && msg.room?.members?.length === 2,
      "host seeing second player"
    );
    const bJoined = waitFor(
      b.ws,
      (msg) => msg.type === "room_state" && msg.room?.code === code && msg.room?.members?.length === 2,
      "joiner entering room"
    );
    b.ws.send(JSON.stringify({ type: "join_room", code }));
    await Promise.all([aSeesTwo, bJoined]);

    await markReady(a, b, a.userId, code);
    await markReady(b, a, b.userId, code);

    const aStart = waitFor(
      a.ws,
      (msg) => msg.type === "game_start" && msg.room?.code === code,
      "game start on host"
    );
    const bStart = waitFor(
      b.ws,
      (msg) => msg.type === "game_start" && msg.room?.code === code,
      "game start on joiner"
    );
    a.ws.send(JSON.stringify({ type: "start_game" }));
    const [hostStart, joinerStart] = await Promise.all([aStart, bStart]);

    if (!hostStart.room.launching || !joinerStart.room.launching) {
      throw new Error("Room did not enter launching state");
    }
    if (hostStart.room.game_server_url !== EXPECTED_GAME_SERVER_URL) {
      throw new Error("Game start payload lost the assigned game server URL");
    }

    console.log(
      `PARDEX production flow passed: ${URL} room=${code} game_server=${hostStart.room.game_server_url}`
    );
  } finally {
    a.ws.close();
    b.ws.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
