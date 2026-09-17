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

const clients = new Map();
const rooms = new Map();
let shuttingDown = false;

function send(ws, payload) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(payload));
  }
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
    members: room.members.map((member) => ({
      user_id: member.userId,
      display_name: member.displayName,
      ready: member.ready,
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
    send(client.ws, { type: "error", code: "ROOM_NOT_FOUND", message: "Oda bulunamadı." });
    return;
  }
  if (client.roomCode === normalized) {
    broadcastRoom(room);
    return;
  }
  if (room.members.length >= room.maxPlayers) {
    send(client.ws, { type: "error", code: "ROOM_FULL", message: "Oda dolu." });
    return;
  }

  leaveCurrentRoom(client.userId, false);
  room.members.push({
    userId: client.userId,
    displayName: client.displayName,
    ready: false,
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
    members: [{
      userId: client.userId,
      displayName: client.displayName,
      ready: false,
    }],
  };

  rooms.set(code, room);
  client.roomCode = code;
  broadcastRoom(room);
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
    send(client.ws, {
      type: "error",
      code: "RATE_LIMIT",
      message: "Çok fazla istek gönderildi. Lütfen kısa süre bekle.",
    });
    return false;
  }
  return true;
}

function handleMessage(client, raw) {
  if (!allowMessage(client)) return;

  let message;
  try {
    message = JSON.parse(raw.toString("utf8"));
  } catch {
    send(client.ws, { type: "error", code: "BAD_JSON", message: "Geçersiz mesaj." });
    return;
  }

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
      if (!room) return;
      const member = room.members.find((item) => item.userId === client.userId);
      if (!member) return;
      member.ready = Boolean(message.ready);
      broadcastRoom(room);
      break;
    }
    case "ping":
      send(client.ws, { type: "pong", time: Date.now() });
      break;
    default:
      send(client.ws, { type: "error", code: "UNKNOWN_MESSAGE", message: "Bilinmeyen istek." });
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
