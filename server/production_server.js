const fs = require("fs");
const path = require("path");
const Module = require("module");

// Production entrypoint. Load the battle-tested server.js implementation in
// the same module scope and append narrowly scoped guards for deployment-only
// invariants. This keeps server.js usable by the existing protocol smoke tests
// while production gets the stricter behavior below.
const serverPath = path.join(__dirname, "server.js");
const serverSource = fs.readFileSync(serverPath, "utf8") + `

(function installProductionGuards() {
  const singleInstanceGameIds = new Set(["korsanlar"]);
  const GAME_SERVER_RECYCLE_GUARD_MS = 5_000;
  const recycleGuardUntil = new Map();

  function activeRoomForGame(gameId, excludeCode = "") {
    for (const room of runtime.rooms.values()) {
      if (!room || room.code === excludeCode || room.gameId !== gameId) continue;
      if (runtime.roomIsLaunching(room) || runtime.roomIsInGame(room)) return room;
    }
    return null;
  }

  function gameServerIsRecycling(gameId, now = Date.now()) {
    const until = Number(recycleGuardUntil.get(gameId) || 0);
    if (until <= now) {
      recycleGuardUntil.delete(gameId);
      return false;
    }
    return true;
  }

  runtime.wss.on("connection", (ws) => {
    // server_core and server.js have already installed the canonical message
    // dispatcher for this socket. Wrap it once so rejected legacy messages do
    // not continue into the old handler during the same EventEmitter cycle.
    const canonicalListeners = ws.listeners("message");
    ws.removeAllListeners("message");
    ws.on("message", (raw, isBinary) => {
      let message = null;
      try {
        message = JSON.parse(raw.toString("utf8"));
      } catch {
        // Delegate malformed payloads so server_core emits BAD_JSON.
      }

      if (message?.type === "game_ended") {
        runtime.sendError(
          ws,
          "GAME_SERVER_AUTHORITATIVE_REQUIRED",
          "Oyun sonucu yalnız yetkili oyun sunucusu tarafından bildirilebilir."
        );
        return;
      }

      if (message?.type === "start_game") {
        const client = clientForSocket(ws);
        const room = client?.roomCode ? runtime.rooms.get(client.roomCode) : null;
        if (room && singleInstanceGameIds.has(room.gameId)) {
          const activeRoom = activeRoomForGame(room.gameId, room.code);
          if (activeRoom || gameServerIsRecycling(room.gameId)) {
            runtime.sendError(
              ws,
              "GAME_SERVER_BUSY",
              "Korsan oyun sunucusu başka bir aktif maçı çalıştırıyor veya yeni maç için hazırlanıyor. Birkaç saniye sonra tekrar deneyin."
            );
            return;
          }
        }
      }

      const endedGameId = message?.type === "game_server_ended"
        ? String(message.game_id || "").trim()
        : "";
      const endedRoomCode = message?.type === "game_server_ended"
        ? String(message.room_code || "").trim().toUpperCase()
        : "";
      const endedMatchId = message?.type === "game_server_ended"
        ? String(message.match_id || "").trim()
        : "";

      for (const listener of canonicalListeners) listener.call(ws, raw, isBinary);

      // The dedicated server recycles itself only after PARDEX acknowledges
      // game_server_ended. Keep the single-instance allocator closed for a
      // short guard window so a new room cannot receive tickets while that
      // same process is still transitioning from game_over back to lobby.
      if (endedGameId && singleInstanceGameIds.has(endedGameId)) {
        const endedRoom = runtime.rooms.get(endedRoomCode);
        if (
          endedRoom
          && endedRoom.gameId === endedGameId
          && endedRoom.matchId === endedMatchId
          && runtime.roomState(endedRoom) === "ended"
        ) {
          recycleGuardUntil.set(endedGameId, Date.now() + GAME_SERVER_RECYCLE_GUARD_MS);
        }
      }
    });
  });
})();
`;

const serverModule = new Module(serverPath, module);
serverModule.filename = serverPath;
serverModule.paths = Module._nodeModulePaths(path.dirname(serverPath));
require.cache[serverPath] = serverModule;
serverModule._compile(serverSource, serverPath);
