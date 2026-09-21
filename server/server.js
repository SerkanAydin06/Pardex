const http = require("http");
const { WebSocketServer, WebSocket } = require("ws");
const crypto = require("crypto");

const PORT = Number(process.env.PORT || 8765);
const HOST = process.env.HOST || "0.0.0.0";
const KORSAN_GAME_SERVER_URL = String(process.env.KORSAN_GAME_SERVER_URL || "").trim();
const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const MAX_ROOM_SIZE = 8;
const MAX_PAYLOAD_BYTES = 16 * 1024;
const RATE_WINDOW_MS = 10_000;
const RATE_LIMIT_MESSAGES = 40;
const RATE_HARD_LIMIT_MESSAGES = 60;
const VOICE_RATE_WINDOW_MS = 1_000;
const VOICE_RATE_LIMIT_MESSAGES = 20;
const MAX_VOICE_BASE64_CHARS = 6_000;
const VOICE_RELAY_BUFFER_LIMIT_BYTES = 64 * 1024;

const clients = new Map();
const rooms = new Map();
let shuttingDown = false;

function send(ws, payload) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

function sendError(ws, code, message) {
  send(ws, { type: "error", code, message });
}

function sendVoice(ws, payload) {
  if (ws.readyState !== WebSocket.OPEN) return;
  if (ws.bufferedAmount >= VOICE_RELAY_BUFFER_LIMIT_BYTES) return;
  ws.send(JSON.stringify(payload));
}

function safeName(value) {
  const text = String(value || "Pardus").trim().replace(/\s+/g, " ");
  return (text || "Pardus").slice(0, 24);
}

function gameServerUrl(gameId) {
  if (gameId === "korsanlar") return KORSAN_GAME_SERVER_URL;
  return "";
}

function roomCode() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    let code = "";
    const bytes = crypto.randomBytes(5);
    for (let i = 0; i < 5; i += 1) {
      code += ROOM_ALPHABET[bytes[i] % ROOM_ALPHABET.length];
    }
    if (!rooms.has(code)) return code;
  }
  throw new Error("Unable to generate unique room code");
}

function roomPayload(room) {
  return {
    code: room.code,
    game_id: room.gameId,
    game_server_url: gameServerUrl(room.gameId),
    host_id: room.hostId,
    max_players: room.maxPlayers,
    launching: Boolean(room.launching),
    members: room.members.map((member) => ({
      user_id: member.userId,
      display_name: member.displayName,
      ready: member.ready,
      voice_muted: Boolean(member.voiceMuted),
    })),
  };
}

function broadcastRoom(room) {
  const payload = { type: "room_state", room: roomPayload(room) };
  for (const member of room.members) {
    const client = clients.get(member.userId);
    if (client) send(client.ws, payload);
  }
}

function leaveCurrentRoom(userId, notifySelf = true) {
  const client = clients.get(userId);
  if (!client || !client.roomCode) return;

  const room = rooms.get(client.roomCode);
  const previousCode = client.roomCode;
  client.roomCode = "";

  if (!room) {
    if (notifySelf) send(client.ws, { type: "left_room", code: previousCode });
    return;
  }

  room.members = room.members.filter((member) => member.userId !== userId);

  if (room.members.length === 0) {
    rooms.delete(room.code);
  } else {
    if (room.hostId === userId) room.hostId = room.members[0].userId;
    if (room.launching) room.launching = false;
    broadcastRoom(room);
  }

  if (notifySelf) send(client.ws, { type: "left_room", code: previousCode });
}

function syncClientNameToRoom(client) {
  if (!client.roomCode) return;
  const room = rooms.get(client.roomCode);
  if (!room) return;
  const member = room.members.find((item) => item.userId === client.userId);
  if (!member) return;
  member.displayName = client.displayName;
  broadcastRoom(room);
}

function joinRoom(client, code) {
  const normalized = String(code || "").trim().toUpperCase();
  const room = rooms.get(normalized);
  if (!room) {
    sendError(client.ws, "ROOM_NOT_FOUND", "Oda bulunamadı.");
    return;
  }
  if (room.launching) {
    sendError(client.ws, "ROOM_IN_GAME", "Bu oda oyunu başlatıyor.");
    return;
  }
  if (client.roomCode === normalized) {
    broadcastRoom(room);
    return;
  }
  if (room.members.length >= room.maxPlayers) {
    sendError(client.ws, "ROOM_FULL", "Oda dolu.");
    return;
  }

  leaveCurrentRoom(client.userId, false);
  room.members.push({
    userId: client.userId,
    displayName: client.displayName,
    ready: false,
    voiceMuted: false,
  });
  client.roomCode = room.code;
  broadcastRoom(room);
}

function createRoom(client, message) {
  leaveCurrentRoom(client.userId, false);

  const code = roomCode();
  const maxPlayers = Math.max(2, Math.min(MAX_ROOM_SIZE, Number(message.max_players || 4)));
  const gameId = String(message.game_id || "korsanlar").slice(0, 32);
  const room = {
    code,
    gameId,
    hostId: client.userId,
    maxPlayers,
    launching: false,
    members: [{
      userId: client.userId,
      displayName: client.displayName,
      ready: false,
      voiceMuted: false,
    }],
  };

  rooms.set(code, room);
  client.roomCode = code;
  broadcastRoom(room);
}

function startRoomGame(client) {
  if (!client.roomCode) {
    sendError(client.ws, "NO_ROOM", "Önce bir odaya katılmalısın.");
    return;
  }

  const room = rooms.get(client.roomCode);
  if (!room) {
    sendError(client.ws, "ROOM_NOT_FOUND", "Oda bulunamadı.");
    return;
  }
  if (room.hostId !== client.userId) {
    sendError(client.ws, "NOT_HOST", "Oyunu yalnız oda kurucusu başlatabilir.");
    return;
  }
  if (room.launching) return;
  if (room.members.length < 2) {
    sendError(client.ws, "NOT_ENOUGH_PLAYERS", "Oyunu başlatmak için en az 2 oyuncu gerekli.");
    return;
  }
  if (!room.members.every((member) => member.ready)) {
    sendError(client.ws, "PLAYERS_NOT_READY", "Tüm oyuncular hazır olmalı.");
    return;
  }
  if (!gameServerUrl(room.gameId)) {
    sendError(client.ws, "GAME_SERVER_UNAVAILABLE", "Bu oyun için PARDEX oyun sunucusu hazır değil.");
    return;
  }

  room.launching = true;
  broadcastRoom(room);
  const payload = {
    type: "game_start",
    game_id: room.gameId,
    room: roomPayload(room),
    started_by: client.userId,
    started_at: Date.now(),
  };
  for (const member of room.members) {
    const memberClient = clients.get(member.userId);
    if (memberClient) send(memberClient.ws, payload);
  }
}

function allowVoiceFrame(client) {
  const now = Date.now();
  if (now - client.voiceRateWindowStartedAt >= VOICE_RATE_WINDOW_MS) {
    client.voiceRateWindowStartedAt = now;
    client.voiceRateMessageCount = 0;
  }

  client.voiceRateMessageCount += 1;
  if (client.voiceRateMessageCount > VOICE_RATE_LIMIT_MESSAGES) {
    return false;
  }
  return true;
}

function setVoiceState(client, muted) {
  if (!client.roomCode) return;
  const room = rooms.get(client.roomCode);
  if (!room) return;
  const member = room.members.find((item) => item.userId === client.userId);
  if (!member) return;
  member.voiceMuted = Boolean(muted);
  broadcastRoom(room);
}

function relayVoiceFrame(client, message) {
  if (!client.roomCode) return;
  const room = rooms.get(client.roomCode);
  if (!room) return;

  const member = room.members.find((item) => item.userId === client.userId);
  if (!member || member.voiceMuted) return;

  const pcm = String(message.pcm || "");
  if (!pcm || pcm.length > MAX_VOICE_BASE64_CHARS) return;

  const sequence = Number.isFinite(Number(message.seq))
    ? Math.max(0, Math.floor(Number(message.seq)))
    : 0;

  const payload = {
    type: "voice_frame",
    user_id: client.userId,
    seq: sequence,
    pcm,
  };

  for (const roomMember of room.members) {
    if (roomMember.userId === client.userId) continue;
    const target = clients.get(roomMember.userId);
    if (target) sendVoice(target.ws, payload);
  }
}

function allowMessage(client) {
  const now = Date.now();
  if (now - client.rateWindowStartedAt >= RATE_WINDOW_MS) {
    client.rateWindowStartedAt = now;
    client.rateMessageCount = 0;
  }

  client.rateMessageCount += 1;
  if (client.rateMessageCount > RATE_HARD_LIMIT_MESSAGES) {
    client.ws.close(1008, "Rate limit exceeded");
    return false;
  }
  if (client.rateMessageCount > RATE_LIMIT_MESSAGES) {
    sendError(client.ws, "RATE_LIMIT", "Çok fazla istek gönderildi. Lütfen kısa süre bekle.");
    return false;
  }
  return true;
}

function handleMessage(client, raw) {
  let message;
  try {
    message = JSON.parse(raw.toString("utf8"));
  } catch {
    sendError(client.ws, "BAD_JSON", "Geçersiz mesaj.");
    return;
  }

  if (message.type === "voice_frame") {
    if (!allowVoiceFrame(client)) return;
    relayVoiceFrame(client, message);
    return;
  }

  if (!allowMessage(client)) return;

  switch (message.type) {
    case "hello":
      client.displayName = safeName(message.display_name);
      send(client.ws, {
        type: "welcome",
        user_id: client.userId,
        display_name: client.displayName,
      });
      syncClientNameToRoom(client);
      break;
    case "create_room":
      createRoom(client, message);
      break;
    case "join_room":
      joinRoom(client, message.code);
      break;
    case "leave_room":
      leaveCurrentRoom(client.userId, true);
      break;
    case "set_ready": {
      if (!client.roomCode) return;
      const room = rooms.get(client.roomCode);
      if (!room || room.launching) return;
      const member = room.members.find((item) => item.userId === client.userId);
      if (!member) return;
      member.ready = Boolean(message.ready);
      broadcastRoom(room);
      break;
    }
    case "start_game":
      startRoomGame(client);
      break;
    case "voice_state":
      setVoiceState(client, message.muted);
      break;
    case "ping":
      send(client.ws, { type: "pong", time: Date.now() });
      break;
    default:
      sendError(client.ws, "UNKNOWN_MESSAGE", "Bilinmeyen istek.");
  }
}

const httpServer = http.createServer((req, res) => {
  if (req.url === "/health") {
    const status = shuttingDown ? 503 : 200;
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      ok: !shuttingDown,
      rooms: rooms.size,
      clients: clients.size,
      korsanGameServerAssigned: Boolean(KORSAN_GAME_SERVER_URL),
      voiceRelay: true,
    }));
    return;
  }

  res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("PARDEX Online server\n");
});

const wss = new WebSocketServer({
  server: httpServer,
  maxPayload: MAX_PAYLOAD_BYTES,
});

wss.on("connection", (ws) => {
  if (shuttingDown) {
    ws.close(1012, "Service restarting");
    return;
  }

  const userId = crypto.randomUUID();
  const client = {
    userId,
    displayName: "Pardus",
    roomCode: "",
    rateWindowStartedAt: Date.now(),
    rateMessageCount: 0,
    voiceRateWindowStartedAt: Date.now(),
    voiceRateMessageCount: 0,
    ws,
  };
  clients.set(userId, client);

  ws.on("message", (raw) => handleMessage(client, raw));
  ws.on("close", () => {
    leaveCurrentRoom(userId, false);
    clients.delete(userId);
  });
  ws.on("error", () => {});
});

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`PARDEX Online shutting down (${signal})`);

  for (const client of clients.values()) {
    client.ws.close(1012, "PARDEX Online restarting");
  }

  wss.close(() => {});
  httpServer.close(() => process.exit(0));

  setTimeout(() => process.exit(1), 5000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

httpServer.listen(PORT, HOST, () => {
  console.log(`PARDEX Online listening on ${HOST}:${PORT}`);
});
