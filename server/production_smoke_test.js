// Live PARDEX room-to-game launch smoke test with exact Railway deploy verification.
const crypto = require("crypto");
const WebSocket = require("ws");

const URL = process.env.PARDEX_ONLINE_URL || "wss://pardex-online-production.up.railway.app";
const EXPECTED_GAME_SERVER_URL = process.env.PARDEX_GAME_SERVER_URL || "wss://korsan-game-production.up.railway.app";
const EXPECTED_DEPLOY_COMMIT = String(process.env.EXPECTED_DEPLOY_COMMIT || "").trim().toLowerCase();
const HTTP_BASE_URL = URL.replace(/^ws/, "http").replace(/\/+$/, "");
const HEALTH_URL = `${HTTP_BASE_URL}/health`;
const DEPLOYMENT_URL = `${HTTP_BASE_URL}/deployment`;
const TIMEOUT_MS = 15000;
const DEPLOYMENT_WAIT_MS = Math.max(15_000, Number(process.env.DEPLOYMENT_WAIT_MS || 180_000));
const DEPLOYMENT_POLL_MS = 3_000;

// Stable per-name keys so repeated CI runs reuse the same production accounts.
function identityKeyFor(name) {
  return crypto.createHash("sha256").update(`pardex-production-smoke:${name}`).digest("hex");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  const contentType = String(response.headers.get("content-type") || "").toLowerCase();
  if (!contentType.includes("application/json")) {
    throw new Error(`${url} is not serving deployment JSON yet`);
  }
  return response.json();
}

async function fetchHealth() {
  return fetchJson(HEALTH_URL);
}

async function waitForExpectedDeployment() {
  if (!EXPECTED_DEPLOY_COMMIT) {
    console.log("No EXPECTED_DEPLOY_COMMIT provided; skipping exact deployment SHA gate.");
    return null;
  }

  const deadline = Date.now() + DEPLOYMENT_WAIT_MS;
  let lastObserved = "<unavailable>";
  let lastError = "";

  while (Date.now() < deadline) {
    try {
      const deployment = await fetchJson(DEPLOYMENT_URL);
      const deployedCommit = String(deployment.commitSha || "").trim().toLowerCase();
      lastObserved = deployedCommit || "<empty>";
      if (deployedCommit === EXPECTED_DEPLOY_COMMIT) {
        console.log(
          `PARDEX production commit verified: ${deployedCommit} deployment=${deployment.deploymentId || "<unknown>"}`
        );
        return deployment;
      }
      lastError = "";
    } catch (error) {
      lastError = error.message;
    }
    await sleep(DEPLOYMENT_POLL_MS);
  }

  const detail = lastError ? ` last_error=${lastError}` : "";
  throw new Error(
    `Railway did not serve expected commit ${EXPECTED_DEPLOY_COMMIT} within ${DEPLOYMENT_WAIT_MS}ms; last_observed=${lastObserved}.${detail}`
  );
}

function connect(name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL);
    const timer = setTimeout(() => reject(new Error(`Timeout connecting ${name}`)), TIMEOUT_MS);

    ws.on("open", () => {
      ws.send(JSON.stringify({ type: "hello", display_name: name, identity_key: identityKeyFor(name) }));
    });

    ws.on("message", (raw) => {
      const msg = JSON.parse(raw.toString("utf8"));
      if (msg.type === "welcome") {
        clearTimeout(timer);
        if (msg.room_lifecycle_enabled !== true) {
          reject(new Error(`${name} welcome did not advertise room lifecycle support`));
          return;
        }
        resolve({ ws, userId: msg.user_id });
      } else if (msg.type === "error") {
        clearTimeout(timer);
        reject(new Error(`${name} hello rejected: ${msg.code} ${msg.message}`));
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
  const deployment = await waitForExpectedDeployment();
  const health = await fetchHealth();
  if (health.accountRecovery !== true) {
    throw new Error("Production /health does not report accountRecovery=true");
  }
  if (health.roomLifecycle !== true) {
    throw new Error("Production /health does not report roomLifecycle=true");
  }
  const voiceRelayEnabled = health.voiceRelay === true;
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
    if (created.room.state !== "lobby") throw new Error(`Expected lobby state, got ${created.room.state}`);
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

    const voiceState = waitFor(
      a.ws,
      (msg) => msg.type === "room_state"
        && msg.room?.code === code
        && msg.room.members.some((m) => m.user_id === b.userId && m.voice_muted === false),
      "voice state sync"
    );
    b.ws.send(JSON.stringify({ type: "voice_state", muted: false }));
    await voiceState;

    if (voiceRelayEnabled) {
      const voiceRelay = waitFor(
        a.ws,
        (msg) => msg.type === "voice_frame"
          && msg.user_id === b.userId
          && msg.seq === 3
          && msg.pcm === "AQIDBA==",
        "voice relay"
      );
      b.ws.send(JSON.stringify({ type: "voice_frame", seq: 3, pcm: "AQIDBA==" }));
      await voiceRelay;
    }

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

    if (!hostStart.room.launching || !joinerStart.room.launching || hostStart.room.state !== "launching") {
      throw new Error("Room did not enter launching state");
    }
    if (!hostStart.match_id || hostStart.match_id !== hostStart.room.match_id) {
      throw new Error("Game start payload is missing stable match_id");
    }
    if (hostStart.room.game_server_url !== EXPECTED_GAME_SERVER_URL) {
      throw new Error("Game start payload lost the assigned game server URL");
    }

    console.log(
      `PARDEX production flow passed: commit=${deployment?.commitSha || "unchecked"} ${URL} room=${code} match=${hostStart.match_id} state=${hostStart.room.state} voice=${voiceRelayEnabled ? "ok" : "disabled"} game_server=${hostStart.room.game_server_url}`
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
