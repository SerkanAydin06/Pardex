const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const Module = require("module");
const { WebSocket } = require("ws");

// server_core owns the main HTTP/WebSocket protocol. Decorate the bootstrap so
// deployment metadata and the trusted game-server control protocol can evolve
// without duplicating the social/session implementation.
const originalCreateServer = http.createServer.bind(http);
http.createServer = (requestListener) => originalCreateServer((req, res) => {
  if (req.url === "/deployment") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      commitSha: String(process.env.RAILWAY_GIT_COMMIT_SHA || "").trim(),
      deploymentId: String(process.env.RAILWAY_DEPLOYMENT_ID || "").trim(),
    }));
    return;
  }
  if (req.url === "/game-control-health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      ok: true,
      twoPhaseGameHandoff: true,
      authoritativeGameEnd: true,
      gameServerTokenConfigured: Boolean(String(process.env.PARDEX_GAME_SERVER_TOKEN || "").trim()),
    }));
    return;
  }
  requestListener(req, res);
});

// Load server_core with a deliberately small runtime export appended in memory.
// This keeps server_core the single source of truth for rooms, sessions and
// social state while allowing this bootstrap to add the dedicated-game control
// channel. The source file on disk is never rewritten at runtime.
const corePath = path.join(__dirname, "server_core.js");
const coreSource = fs.readFileSync(corePath, "utf8") + `\nmodule.exports.__pardexRuntime = {\n  wss, rooms, clients, gameLaunchTickets, gameLaunchTicketHash,\n  roomIsLaunching, roomIsInGame, roomState, markMemberGameConnected,\n  send, sendError, clearGameLaunchTicketsForMatch, broadcastRoom,\n  pushRoomPresence, sendRoomLifecycleEvent\n};\n`;
const coreModule = new Module(corePath, module);
coreModule.filename = corePath;
coreModule.paths = Module._nodeModulePaths(path.dirname(corePath));
require.cache[corePath] = coreModule;
coreModule._compile(coreSource, corePath);

const runtime = coreModule.exports.__pardexRuntime;
const GAME_ADMISSION_TOKEN_TTL_MS = Math.max(
  5_000,
  Number(process.env.GAME_ADMISSION_TOKEN_TTL_MS || 30_000)
);
const GAME_SERVER_TOKEN = String(process.env.PARDEX_GAME_SERVER_TOKEN || "").trim();
const admissionTokens = new Map();

function hashToken(value) {
  return crypto.createHash("sha256").update(String(value || ""), "utf8").digest("hex");
}

function secretEquals(left, right) {
  if (!left || !right) return false;
  const a = crypto.createHash("sha256").update(String(left), "utf8").digest();
  const b = crypto.createHash("sha256").update(String(right), "utf8").digest();
  return crypto.timingSafeEqual(a, b);
}

function clientForSocket(ws) {
  for (const client of runtime.clients.values()) {
    if (client?.ws === ws) return client;
  }
  return null;
}

function clearHelloTimer(ws) {
  const client = clientForSocket(ws);
  if (!client?.helloTimer) return;
  clearTimeout(client.helloTimer);
  client.helloTimer = null;
}

function pruneAdmissionTokens(now = Date.now()) {
  for (const [tokenHash, record] of admissionTokens.entries()) {
    if (now >= record.expiresAt || record.ws?.readyState !== WebSocket.OPEN) {
      admissionTokens.delete(tokenHash);
    }
  }
}

function clearAdmissionsForMatch(matchId) {
  const normalized = String(matchId || "").trim();
  if (!normalized) return;
  for (const [tokenHash, record] of admissionTokens.entries()) {
    if (record.matchId === normalized) admissionTokens.delete(tokenHash);
  }
}

function activeRoomForTicket(record) {
  const room = runtime.rooms.get(record.roomCode);
  if (!room) return null;
  if (!runtime.roomIsLaunching(room) && !runtime.roomIsInGame(room)) return null;
  if (room.matchId !== record.matchId || room.gameId !== record.gameId) return null;
  return room;
}

function handleTicketVerify(ws, message) {
  const matchId = String(message.match_id || "").trim();
  const ticket = String(message.launch_ticket || "").trim();
  const requestedGameId = String(message.game_id || "").trim();
  if (!matchId || !ticket) {
    runtime.sendError(ws, "GAME_TICKET_REQUIRED", "Oyun bağlantısı için geçerli bir PARDEX ticket gerekli.");
    return;
  }

  pruneAdmissionTokens();
  const ticketHash = runtime.gameLaunchTicketHash(ticket);
  const record = runtime.gameLaunchTickets.get(ticketHash);
  if (!record) {
    runtime.sendError(ws, "GAME_TICKET_INVALID", "PARDEX oyun ticket'ı geçersiz veya daha önce kullanılmış.");
    return;
  }
  if (Date.now() >= record.expiresAt) {
    runtime.gameLaunchTickets.delete(ticketHash);
    runtime.sendError(ws, "GAME_TICKET_EXPIRED", "PARDEX oyun ticket'ının süresi doldu.");
    return;
  }
  if (record.matchId !== matchId) {
    runtime.sendError(ws, "MATCH_MISMATCH", "Oyun oturumu kimliği ticket ile eşleşmiyor.");
    return;
  }
  if (requestedGameId && requestedGameId !== record.gameId) {
    runtime.sendError(ws, "GAME_MISMATCH", "Oyun kimliği ticket ile eşleşmiyor.");
    return;
  }

  const room = activeRoomForTicket(record);
  if (!room) {
    runtime.gameLaunchTickets.delete(ticketHash);
    runtime.sendError(ws, "GAME_SESSION_CLOSED", "PARDEX oyun oturumu artık aktif değil.");
    return;
  }
  const member = room.members.find((item) =>
    item.userId === record.userId
    && (!record.accountId || item.accountId === record.accountId)
  );
  if (!member) {
    runtime.gameLaunchTickets.delete(ticketHash);
    runtime.sendError(ws, "GAME_MEMBER_NOT_FOUND", "Bu ticket artık oda üyesiyle eşleşmiyor.");
    return;
  }

  // Phase 1 consumes the launch ticket but deliberately does NOT mark the
  // player in_game. That only happens after the Korsan dedicated server has
  // actually inserted the player into its authoritative lobby.
  runtime.gameLaunchTickets.delete(ticketHash);
  clearHelloTimer(ws);
  const admissionToken = crypto.randomBytes(32).toString("base64url");
  const expiresAt = Date.now() + GAME_ADMISSION_TOKEN_TTL_MS;
  admissionTokens.set(hashToken(admissionToken), {
    matchId: record.matchId,
    roomCode: record.roomCode,
    gameId: record.gameId,
    userId: record.userId,
    accountId: record.accountId || "",
    expiresAt,
    ws,
  });
  runtime.send(ws, {
    type: "game_ticket_ok",
    game_id: record.gameId,
    match_id: record.matchId,
    room_code: record.roomCode,
    user_id: record.userId,
    admission_token: admissionToken,
    admission_token_expires_at: expiresAt,
  });
}

function handleGameAdmitted(ws, message) {
  pruneAdmissionTokens();
  const token = String(message.admission_token || "").trim();
  const matchId = String(message.match_id || "").trim();
  const requestedGameId = String(message.game_id || "").trim();
  const tokenHash = hashToken(token);
  const record = admissionTokens.get(tokenHash);
  if (!token || !record || record.ws !== ws) {
    runtime.sendError(ws, "GAME_ADMISSION_INVALID", "PARDEX oyun kabul anahtarı geçersiz veya kullanılmış.");
    return;
  }
  if (Date.now() >= record.expiresAt) {
    admissionTokens.delete(tokenHash);
    runtime.sendError(ws, "GAME_ADMISSION_EXPIRED", "PARDEX oyun kabul anahtarının süresi doldu.");
    return;
  }
  if (record.matchId !== matchId || (requestedGameId && requestedGameId !== record.gameId)) {
    runtime.sendError(ws, "MATCH_MISMATCH", "PARDEX oyun kabul bilgileri maçla eşleşmiyor.");
    return;
  }

  const room = activeRoomForTicket(record);
  if (!room) {
    admissionTokens.delete(tokenHash);
    runtime.sendError(ws, "GAME_SESSION_CLOSED", "PARDEX oyun oturumu artık aktif değil.");
    return;
  }
  const member = room.members.find((item) =>
    item.userId === record.userId
    && (!record.accountId || item.accountId === record.accountId)
  );
  if (!member) {
    admissionTokens.delete(tokenHash);
    runtime.sendError(ws, "GAME_MEMBER_NOT_FOUND", "Oyuncu artık bu PARDEX maçının üyesi değil.");
    return;
  }

  admissionTokens.delete(tokenHash);
  runtime.markMemberGameConnected(room, member);
  runtime.send(ws, {
    type: "game_admitted_ok",
    game_id: room.gameId,
    match_id: room.matchId,
    room_code: room.code,
    user_id: member.userId,
    game_connected_at: member.gameConnectedAt,
  });
}

function sanitizeGameResult(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const serialized = JSON.stringify(value);
  if (serialized.length > 8_000) return { reason: "result_too_large" };
  return JSON.parse(serialized);
}

function finishRoomFromGameServer(room, result) {
  runtime.clearGameLaunchTicketsForMatch(room.matchId);
  clearAdmissionsForMatch(room.matchId);
  room.state = "ended";
  room.endedAt = Date.now();
  for (const member of room.members) {
    member.gameState = "ended";
    member.ready = false;
  }
  runtime.broadcastRoom(room);
  runtime.pushRoomPresence(room);
  runtime.sendRoomLifecycleEvent(room, "game_ended", {
    match_id: room.matchId,
    ended_at: room.endedAt,
    result,
    source: "game_server",
  });
}

function handleGameServerEnded(ws, message) {
  clearHelloTimer(ws);
  if (!GAME_SERVER_TOKEN || !secretEquals(GAME_SERVER_TOKEN, message.server_token)) {
    runtime.sendError(ws, "GAME_SERVER_UNAUTHORIZED", "Oyun sunucusu doğrulanamadı.");
    return;
  }
  const roomCode = String(message.room_code || "").trim().toUpperCase();
  const matchId = String(message.match_id || "").trim();
  const gameId = String(message.game_id || "").trim();
  const room = runtime.rooms.get(roomCode);
  if (!room || !matchId || room.matchId !== matchId || room.gameId !== gameId) {
    runtime.sendError(ws, "MATCH_MISMATCH", "Oyun sunucusu sonucu aktif PARDEX maçıyla eşleşmiyor.");
    return;
  }

  if (runtime.roomState(room) === "ended") {
    runtime.send(ws, {
      type: "game_server_ended_ok",
      game_id: room.gameId,
      match_id: room.matchId,
      room_code: room.code,
      ended_at: room.endedAt,
      duplicate: true,
    });
    return;
  }
  if (!runtime.roomIsLaunching(room) && !runtime.roomIsInGame(room)) {
    runtime.sendError(ws, "GAME_NOT_ACTIVE", "Bu PARDEX maçında aktif oyun yok.");
    return;
  }

  const result = sanitizeGameResult(message.result);
  finishRoomFromGameServer(room, result);
  runtime.send(ws, {
    type: "game_server_ended_ok",
    game_id: room.gameId,
    match_id: room.matchId,
    room_code: room.code,
    ended_at: room.endedAt,
    duplicate: false,
  });
}

function installGameControlProtocol(ws) {
  // server_core registered its message listener earlier in the WSS connection
  // callback. Replace that listener with a dispatcher that handles only the
  // new dedicated-game messages here and delegates everything else unchanged.
  const coreListeners = ws.listeners("message");
  ws.removeAllListeners("message");
  ws.on("message", (raw, isBinary) => {
    let message = null;
    try {
      message = JSON.parse(raw.toString("utf8"));
    } catch {
      // Let server_core produce the canonical BAD_JSON response.
    }

    if (message?.type === "game_ticket_verify") {
      handleTicketVerify(ws, message);
      return;
    }
    if (message?.type === "game_admitted") {
      handleGameAdmitted(ws, message);
      return;
    }
    if (message?.type === "game_server_ended") {
      handleGameServerEnded(ws, message);
      return;
    }

    for (const listener of coreListeners) listener.call(ws, raw, isBinary);
  });
  ws.on("close", () => {
    for (const [tokenHash, record] of admissionTokens.entries()) {
      if (record.ws === ws) admissionTokens.delete(tokenHash);
    }
  });
}

runtime.wss.on("connection", installGameControlProtocol);
