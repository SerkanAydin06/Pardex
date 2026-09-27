const http = require("http");
const path = require("path");
const { WebSocketServer, WebSocket } = require("ws");
const crypto = require("crypto");
const { SocialStore } = require("./social_store");

const PORT = Number(process.env.PORT || 8765);
const HOST = process.env.HOST || "0.0.0.0";
const KORSAN_GAME_SERVER_URL = String(process.env.KORSAN_GAME_SERVER_URL || "").trim();
const SESSION_GRACE_MS = Math.max(1000, Number(process.env.SESSION_GRACE_MS || 30_000));
const ROOM_INVITE_TTL_MS = Math.max(15_000, Number(process.env.ROOM_INVITE_TTL_MS || 60_000));
const HELLO_TIMEOUT_MS = Math.max(500, Number(process.env.HELLO_TIMEOUT_MS || 10_000));
// PARDEX voice is disabled on the client; keep the relay off unless explicitly enabled.
const VOICE_RELAY_ENABLED = ["1", "true", "yes"].includes(
  String(process.env.PARDEX_VOICE_RELAY_ENABLED || "").trim().toLowerCase()
);
const SOCIAL_DATA_PATH = String(
  process.env.PARDEX_SOCIAL_DATA_PATH || path.join(__dirname, "data", "social.json")
).trim();
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
const PRESENCE_VALUES = new Set(["online", "away", "busy"]);

const clients = new Map();
const rooms = new Map();
const resumeTokens = new Map();
const roomInvites = new Map();
const social = new SocialStore(SOCIAL_DATA_PATH);
let shuttingDown = false;

function send(ws, payload) {
  if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
}

function sendError(ws, code, message) {
  send(ws, { type: "error", code, message });
}

function sendNotice(ws, code, message) {
  send(ws, { type: "social_notice", code, message });
}

function sendVoice(ws, payload) {
  if (ws?.readyState !== WebSocket.OPEN) return;
  if (ws.bufferedAmount >= VOICE_RELAY_BUFFER_LIMIT_BYTES) return;
  ws.send(JSON.stringify(payload));
}

function safeName(value) {
  const text = String(value || "Pardus").trim().replace(/\s+/g, " ");
  return (text || "Pardus").slice(0, 24);
}

function safePresence(value) {
  const normalized = String(value || "online").trim().toLowerCase();
  return PRESENCE_VALUES.has(normalized) ? normalized : "online";
}

function createResumeToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function gameServerUrl(gameId) {
  if (gameId === "korsanlar") return KORSAN_GAME_SERVER_URL;
  return "";
}

function gameDisplayName(gameId) {
  if (gameId === "korsanlar") return "Korsanların Hazinesi";
  return gameId || "PARDEX Oyunu";
}

function roomCode() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    let code = "";
    const bytes = crypto.randomBytes(5);
    for (let i = 0; i < 5; i += 1) code += ROOM_ALPHABET[bytes[i] % ROOM_ALPHABET.length];
    if (!rooms.has(code)) return code;
  }
  throw new Error("Unable to generate unique room code");
}

function clientsForAccount(accountId) {
  const result = [];
  if (!accountId) return result;
  for (const client of clients.values()) {
    if (
      client.accountId === accountId
      && client.helloReceived
      && client.ws?.readyState === WebSocket.OPEN
    ) result.push(client);
  }
  return result;
}

function isAccountOnline(accountId) {
  return clientsForAccount(accountId).length > 0;
}

function presenceForAccount(accountId) {
  const connected = clientsForAccount(accountId);
  if (connected.length === 0) {
    return {
      presence: "offline",
      in_room: false,
      in_game: false,
      game_id: "",
      game_name: "",
      room_joinable: false,
      room_member_count: 0,
      room_max_players: 0,
    };
  }

  let manualPresence = "online";
  if (connected.some((client) => client.presenceStatus === "busy")) manualPresence = "busy";
  else if (connected.every((client) => client.presenceStatus === "away")) manualPresence = "away";

  let chosenRoom = null;
  for (const client of connected) {
    if (!client.roomCode) continue;
    const room = rooms.get(client.roomCode);
    if (!room) continue;
    if (!room.members.some((member) => member.userId === client.userId)) continue;
    if (!chosenRoom || room.launching) chosenRoom = room;
    if (room.launching) break;
  }

  if (!chosenRoom) {
    return {
      presence: manualPresence,
      in_room: false,
      in_game: false,
      game_id: "",
      game_name: "",
      room_joinable: false,
      room_member_count: 0,
      room_max_players: 0,
    };
  }

  return {
    presence: chosenRoom.launching ? "in_game" : manualPresence,
    in_room: true,
    in_game: Boolean(chosenRoom.launching),
    game_id: chosenRoom.gameId,
    game_name: gameDisplayName(chosenRoom.gameId),
    room_joinable: !chosenRoom.launching && chosenRoom.members.length < chosenRoom.maxPlayers,
    room_member_count: chosenRoom.members.length,
    room_max_players: chosenRoom.maxPlayers,
  };
}

function enrichFriendProfile(profile) {
  if (!profile) return profile;
  return { ...profile, ...presenceForAccount(profile.account_id) };
}

function buildSocialState(accountId) {
  const state = social.socialState(accountId, isAccountOnline);
  if (!state) return null;
  if (state.self) state.self = enrichFriendProfile(state.self);
  state.friends = (state.friends || []).map(enrichFriendProfile).sort((a, b) => {
    const rank = { in_game: 5, online: 4, busy: 3, away: 2, offline: 1 };
    const difference = (rank[b.presence] || 0) - (rank[a.presence] || 0);
    return difference || a.display_name.localeCompare(b.display_name);
  });
  state.incoming_requests = (state.incoming_requests || []).map((profile) => ({
    ...profile,
    presence: profile.online ? "online" : "offline",
  }));
  state.outgoing_requests = (state.outgoing_requests || []).map((profile) => ({
    ...profile,
    presence: profile.online ? "online" : "offline",
  }));
  return state;
}

function pushSocialState(accountId) {
  if (!accountId) return;
  const state = buildSocialState(accountId);
  if (!state) return;
  for (const client of clientsForAccount(accountId)) send(client.ws, { type: "social_state", state });
}

function pushRelatedSocialStates(accountId) {
  if (!accountId) return;
  for (const relatedId of social.relatedAccountIds(accountId)) pushSocialState(relatedId);
}

function pushRoomPresence(room, extraAccountId = "") {
  const ids = new Set();
  if (extraAccountId) ids.add(extraAccountId);
  if (room) {
    for (const member of room.members) {
      if (member.accountId) ids.add(member.accountId);
    }
  }
  for (const accountId of ids) pushRelatedSocialStates(accountId);
}

function requireSocialAccount(client) {
  if (client.helloReceived && client.accountId && social.getAccount(client.accountId)) return true;
  sendError(client.ws, "SOCIAL_NOT_READY", "PARDEX sosyal kimliği henüz hazır değil.");
  return false;
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
      account_id: member.accountId || "",
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
    if (client?.ws) send(client.ws, payload);
  }
}

function closeRoomInvite(invite, reason = "closed") {
  if (!invite) return;
  if (invite.timer) clearTimeout(invite.timer);
  roomInvites.delete(invite.id);
  for (const target of clientsForAccount(invite.toAccountId)) {
    send(target.ws, { type: "room_invite_closed", invite_id: invite.id, reason });
  }
}

function cancelInvitesForRoom(code, reason = "room_closed") {
  for (const invite of [...roomInvites.values()]) {
    if (invite.roomCode === code) closeRoomInvite(invite, reason);
  }
}

function invitePayload(invite, room) {
  const inviter = social.getAccount(invite.fromAccountId);
  return {
    id: invite.id,
    room_code: room.code,
    game_id: room.gameId,
    game_name: gameDisplayName(room.gameId),
    from_account_id: invite.fromAccountId,
    from_display_name: inviter?.display_name || "Pardus",
    member_count: room.members.length,
    max_players: room.maxPlayers,
    expires_at: invite.expiresAt,
  };
}

function sendRoomInvite(client, targetAccountId) {
  if (!requireSocialAccount(client)) return;
  const targetId = String(targetAccountId || "").trim();
  if (!targetId || targetId === client.accountId) {
    sendError(client.ws, "INVALID_INVITE_TARGET", "Geçerli bir arkadaş seçmelisin.");
    return;
  }
  if (social.relationshipBetween(client.accountId, targetId) !== "friend") {
    sendError(client.ws, "NOT_FRIENDS", "Oda daveti yalnız arkadaşlara gönderilebilir.");
    return;
  }
  if (!client.roomCode) {
    sendError(client.ws, "NO_ROOM", "Arkadaşını davet etmek için önce bir odaya katılmalısın.");
    return;
  }

  const room = rooms.get(client.roomCode);
  if (!room || !room.members.some((member) => member.userId === client.userId)) {
    sendError(client.ws, "ROOM_NOT_FOUND", "Aktif odan bulunamadı.");
    return;
  }
  if (room.launching) {
    sendError(client.ws, "ROOM_IN_GAME", "Oyun başlatılırken yeni davet gönderilemez.");
    return;
  }
  if (room.members.length >= room.maxPlayers) {
    sendError(client.ws, "ROOM_FULL", "Oda dolu.");
    return;
  }
  if (room.members.some((member) => member.accountId === targetId)) {
    sendError(client.ws, "ALREADY_IN_ROOM", "Bu arkadaş zaten odada.");
    return;
  }

  const targets = clientsForAccount(targetId);
  if (targets.length === 0) {
    sendError(client.ws, "FRIEND_OFFLINE", "Arkadaşın şu anda çevrimdışı.");
    return;
  }

  for (const existing of [...roomInvites.values()]) {
    if (
      existing.fromAccountId === client.accountId
      && existing.toAccountId === targetId
      && existing.roomCode === room.code
    ) closeRoomInvite(existing, "replaced");
  }

  const now = Date.now();
  const invite = {
    id: crypto.randomUUID(),
    fromAccountId: client.accountId,
    fromUserId: client.userId,
    toAccountId: targetId,
    roomCode: room.code,
    createdAt: now,
    expiresAt: now + ROOM_INVITE_TTL_MS,
    timer: null,
  };
  invite.timer = setTimeout(() => closeRoomInvite(invite, "expired"), ROOM_INVITE_TTL_MS);
  invite.timer.unref?.();
  roomInvites.set(invite.id, invite);

  const payload = { type: "room_invite", invite: invitePayload(invite, room) };
  for (const target of targets) send(target.ws, payload);
  sendNotice(client.ws, "ROOM_INVITE_SENT", "Oda daveti gönderildi.");
}

function respondToRoomInvite(client, inviteId, accept) {
  if (!requireSocialAccount(client)) return;
  const normalizedId = String(inviteId || "").trim();
  const invite = roomInvites.get(normalizedId);
  if (!invite || invite.toAccountId !== client.accountId) {
    sendError(client.ws, "INVITE_NOT_FOUND", "Oda daveti artık geçerli değil.");
    return;
  }
  if (Date.now() >= invite.expiresAt) {
    closeRoomInvite(invite, "expired");
    sendError(client.ws, "INVITE_EXPIRED", "Oda davetinin süresi doldu.");
    return;
  }

  if (!accept) {
    closeRoomInvite(invite, "declined");
    sendNotice(client.ws, "ROOM_INVITE_DECLINED", "Oda daveti reddedildi.");
    for (const inviter of clientsForAccount(invite.fromAccountId)) {
      sendNotice(inviter.ws, "ROOM_INVITE_DECLINED", `${client.displayName} oda davetini reddetti.`);
    }
    return;
  }

  if (social.relationshipBetween(client.accountId, invite.fromAccountId) !== "friend") {
    closeRoomInvite(invite, "not_friends");
    sendError(client.ws, "NOT_FRIENDS", "Davet gönderen kullanıcı artık arkadaş listende değil.");
    return;
  }

  const room = rooms.get(invite.roomCode);
  if (!room) {
    closeRoomInvite(invite, "room_closed");
    sendError(client.ws, "ROOM_NOT_FOUND", "Davet edilen oda artık açık değil.");
    return;
  }
  if (room.launching) {
    closeRoomInvite(invite, "room_in_game");
    sendError(client.ws, "ROOM_IN_GAME", "Bu oda oyunu başlatıyor.");
    return;
  }
  if (room.members.length >= room.maxPlayers) {
    closeRoomInvite(invite, "room_full");
    sendError(client.ws, "ROOM_FULL", "Davet edilen oda doldu.");
    return;
  }

  closeRoomInvite(invite, "accepted");
  joinRoom(client, room.code);
  sendNotice(client.ws, "ROOM_INVITE_ACCEPTED", "Odaya katıldın.");
  for (const inviter of clientsForAccount(invite.fromAccountId)) {
    sendNotice(inviter.ws, "ROOM_INVITE_ACCEPTED", `${client.displayName} odaya katıldı.`);
  }
}

function joinFriendRoom(client, targetAccountId) {
  if (!requireSocialAccount(client)) return;
  const targetId = String(targetAccountId || "").trim();
  if (!targetId || social.relationshipBetween(client.accountId, targetId) !== "friend") {
    sendError(client.ws, "NOT_FRIENDS", "Bu odaya arkadaş üzerinden katılamazsın.");
    return;
  }

  const targetClients = clientsForAccount(targetId);
  if (targetClients.length === 0) {
    sendError(client.ws, "FRIEND_OFFLINE", "Arkadaşın şu anda çevrimdışı.");
    return;
  }

  let room = null;
  for (const target of targetClients) {
    if (!target.roomCode) continue;
    const candidate = rooms.get(target.roomCode);
    if (!candidate) continue;
    if (!candidate.members.some((member) => member.userId === target.userId)) continue;
    room = candidate;
    break;
  }

  if (!room) {
    sendError(client.ws, "FRIEND_NOT_IN_ROOM", "Arkadaşın şu anda katılabileceğin bir odada değil.");
    return;
  }
  if (room.launching) {
    sendError(client.ws, "ROOM_IN_GAME", "Arkadaşının odasında oyun başlamış.");
    return;
  }
  if (room.members.length >= room.maxPlayers) {
    sendError(client.ws, "ROOM_FULL", "Arkadaşının odası dolu.");
    return;
  }

  joinRoom(client, room.code);
  sendNotice(client.ws, "FRIEND_ROOM_JOINED", `${social.getAccount(targetId)?.display_name || "Arkadaşının"} odasına katıldın.`);
}

function leaveCurrentRoom(userId, notifySelf = true) {
  const client = clients.get(userId);
  if (!client || !client.roomCode) return;

  const room = rooms.get(client.roomCode);
  const previousCode = client.roomCode;
  const leavingAccountId = client.accountId;
  client.roomCode = "";

  if (!room) {
    if (notifySelf) send(client.ws, { type: "left_room", code: previousCode });
    pushRelatedSocialStates(leavingAccountId);
    return;
  }

  room.members = room.members.filter((member) => member.userId !== userId);
  if (room.members.length === 0) {
    rooms.delete(room.code);
    cancelInvitesForRoom(room.code, "room_closed");
  } else {
    if (room.hostId === userId) room.hostId = room.members[0].userId;
    if (room.launching) room.launching = false;
    broadcastRoom(room);
  }

  if (notifySelf) send(client.ws, { type: "left_room", code: previousCode });
  pushRelatedSocialStates(leavingAccountId);
  pushRoomPresence(room);
}

function revokeAccountSessions(accountId, replacementClient) {
  if (!accountId) return;
  for (const session of [...clients.values()]) {
    if (session === replacementClient || session.accountId !== accountId) continue;
    if (session.disconnectTimer) {
      clearTimeout(session.disconnectTimer);
      session.disconnectTimer = null;
    }
    leaveCurrentRoom(session.userId, false);
    clients.delete(session.userId);
    resumeTokens.delete(session.resumeToken);
    session.replaced = true;
    const previousSocket = session.ws;
    session.ws = null;
    if (previousSocket?.readyState === WebSocket.OPEN) {
      previousSocket.close(4003, "PARDEX account transferred to another device");
    }
  }
  pushRelatedSocialStates(accountId);
}

function syncClientNameToRoom(client) {
  if (!client.roomCode) return;
  const room = rooms.get(client.roomCode);
  if (!room) return;
  const member = room.members.find((item) => item.userId === client.userId);
  if (!member) return;
  member.displayName = client.displayName;
  member.accountId = client.accountId;
  broadcastRoom(room);
}

function expireDisconnectedClient(client) {
  if (!client || client.replaced || client.ws) return;
  if (clients.get(client.userId) !== client) return;
  leaveCurrentRoom(client.userId, false);
  clients.delete(client.userId);
  resumeTokens.delete(client.resumeToken);
  client.disconnectTimer = null;
}

function detachClient(client, ws) {
  if (!client || client.replaced || client.ws !== ws) return;
  const accountId = client.accountId;
  client.ws = null;
  if (!client.helloReceived) {
    clients.delete(client.userId);
    resumeTokens.delete(client.resumeToken);
    return;
  }
  if (client.disconnectTimer) clearTimeout(client.disconnectTimer);
  client.disconnectTimer = setTimeout(() => expireDisconnectedClient(client), SESSION_GRACE_MS);
  client.disconnectTimer.unref?.();
  pushRelatedSocialStates(accountId);
}

function tryResumeClient(client, resumeToken, expectedAccountId) {
  const token = String(resumeToken || "").trim();
  if (!token) return false;
  const existingUserId = resumeTokens.get(token);
  if (!existingUserId) return false;
  const existing = clients.get(existingUserId);
  if (!existing) {
    resumeTokens.delete(token);
    return false;
  }
  if (existing.accountId && existing.accountId !== expectedAccountId) return false;
  if (existing === client) return true;

  if (existing.disconnectTimer) {
    clearTimeout(existing.disconnectTimer);
    existing.disconnectTimer = null;
  }

  clients.delete(client.userId);
  resumeTokens.delete(client.resumeToken);
  const previousSocket = existing.ws;
  existing.replaced = true;
  existing.ws = null;

  client.userId = existing.userId;
  client.resumeToken = existing.resumeToken;
  client.roomCode = existing.roomCode;
  client.displayName = existing.displayName;
  client.accountId = expectedAccountId;
  client.presenceStatus = existing.presenceStatus || "online";
  client.helloReceived = true;
  clients.set(client.userId, client);
  resumeTokens.set(client.resumeToken, client.userId);

  if (previousSocket && previousSocket !== client.ws) previousSocket.close(4001, "PARDEX session resumed elsewhere");
  return true;
}

function joinRoom(client, code) {
  const normalized = String(code || "").trim().toUpperCase();
  const room = rooms.get(normalized);
  if (!room) return sendError(client.ws, "ROOM_NOT_FOUND", "Oda bulunamadı.");
  if (room.launching) return sendError(client.ws, "ROOM_IN_GAME", "Bu oda oyunu başlatıyor.");
  if (client.roomCode === normalized) {
    broadcastRoom(room);
    return;
  }
  if (room.members.length >= room.maxPlayers) return sendError(client.ws, "ROOM_FULL", "Oda dolu.");

  const oldAccountId = client.accountId;
  leaveCurrentRoom(client.userId, false);
  room.members.push({
    userId: client.userId,
    accountId: client.accountId,
    displayName: client.displayName,
    ready: false,
    voiceMuted: false,
  });
  client.roomCode = room.code;
  broadcastRoom(room);
  pushRelatedSocialStates(oldAccountId);
  pushRoomPresence(room);
}

function createRoom(client, message) {
  leaveCurrentRoom(client.userId, false);
  const code = roomCode();
  const requestedMaxPlayers = Number(message.max_players);
  const maxPlayers = Number.isFinite(requestedMaxPlayers)
    ? Math.max(2, Math.min(MAX_ROOM_SIZE, Math.floor(requestedMaxPlayers)))
    : 4;
  const gameId = String(message.game_id || "korsanlar").slice(0, 32);
  const room = {
    code,
    gameId,
    hostId: client.userId,
    maxPlayers,
    launching: false,
    members: [{
      userId: client.userId,
      accountId: client.accountId,
      displayName: client.displayName,
      ready: false,
      voiceMuted: false,
    }],
  };
  rooms.set(code, room);
  client.roomCode = code;
  broadcastRoom(room);
  pushRoomPresence(room);
}

function startRoomGame(client) {
  if (!client.roomCode) return sendError(client.ws, "NO_ROOM", "Önce bir odaya katılmalısın.");
  const room = rooms.get(client.roomCode);
  if (!room) return sendError(client.ws, "ROOM_NOT_FOUND", "Oda bulunamadı.");
  if (room.hostId !== client.userId) return sendError(client.ws, "NOT_HOST", "Oyunu yalnız oda kurucusu başlatabilir.");
  if (room.launching) return;
  if (room.members.length < 2) return sendError(client.ws, "NOT_ENOUGH_PLAYERS", "Oyunu başlatmak için en az 2 oyuncu gerekli.");
  if (!room.members.every((member) => member.ready)) return sendError(client.ws, "PLAYERS_NOT_READY", "Tüm oyuncular hazır olmalı.");
  if (!gameServerUrl(room.gameId)) return sendError(client.ws, "GAME_SERVER_UNAVAILABLE", "Bu oyun için PARDEX oyun sunucusu hazır değil.");

  room.launching = true;
  cancelInvitesForRoom(room.code, "room_in_game");
  broadcastRoom(room);
  pushRoomPresence(room);
  const payload = {
    type: "game_start",
    game_id: room.gameId,
    room: roomPayload(room),
    started_by: client.userId,
    started_at: Date.now(),
  };
  for (const member of room.members) {
    const memberClient = clients.get(member.userId);
    if (memberClient?.ws) send(memberClient.ws, payload);
  }
}

function reportGameLaunchFailed(client) {
  if (!client.roomCode) return;
  const room = rooms.get(client.roomCode);
  if (!room || !room.launching) return;
  const member = room.members.find((item) => item.userId === client.userId);
  if (!member) return;
  room.launching = false;
  member.ready = false;
  broadcastRoom(room);
  pushRoomPresence(room);
}

function setPresenceStatus(client, value) {
  if (!requireSocialAccount(client)) return;
  client.presenceStatus = safePresence(value);
  send(client.ws, { type: "presence_state", presence: client.presenceStatus });
  pushRelatedSocialStates(client.accountId);
}

function allowVoiceFrame(client) {
  const now = Date.now();
  if (now - client.voiceRateWindowStartedAt >= VOICE_RATE_WINDOW_MS) {
    client.voiceRateWindowStartedAt = now;
    client.voiceRateMessageCount = 0;
  }
  client.voiceRateMessageCount += 1;
  return client.voiceRateMessageCount <= VOICE_RATE_LIMIT_MESSAGES;
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
  if (!VOICE_RELAY_ENABLED) return;
  if (!client.helloReceived || !client.roomCode) return;
  const room = rooms.get(client.roomCode);
  if (!room) return;
  const member = room.members.find((item) => item.userId === client.userId);
  if (!member || member.voiceMuted) return;
  const pcm = String(message.pcm || "");
  if (!pcm || pcm.length > MAX_VOICE_BASE64_CHARS) return;
  const sequence = Number.isFinite(Number(message.seq)) ? Math.max(0, Math.floor(Number(message.seq))) : 0;
  const payload = { type: "voice_frame", user_id: client.userId, seq: sequence, pcm };
  for (const roomMember of room.members) {
    if (roomMember.userId === client.userId) continue;
    const target = clients.get(roomMember.userId);
    if (target?.ws) sendVoice(target.ws, payload);
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
    client.ws?.close(1008, "Rate limit exceeded");
    return false;
  }
  if (client.rateMessageCount > RATE_LIMIT_MESSAGES) {
    sendError(client.ws, "RATE_LIMIT", "Çok fazla istek gönderildi. Lütfen kısa süre bekle.");
    return false;
  }
  return true;
}

function applySocialAction(client, result, otherAccountId) {
  if (!result.ok) return sendError(client.ws, result.code, result.message);
  sendNotice(client.ws, result.code, result.message);
  pushSocialState(client.accountId);
  pushSocialState(otherAccountId);
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
    if (allowVoiceFrame(client)) relayVoiceFrame(client, message);
    return;
  }
  if (!allowMessage(client)) return;

  if (message.type !== "hello" && !client.helloReceived) {
    sendError(client.ws, "SESSION_NOT_READY", "PARDEX oturumu henüz hazır değil.");
    return;
  }

  switch (message.type) {
    case "hello": {
      const recoveryCode = String(message.recovery_code || "").trim();
      let accountId = "";
      let recovered = false;
      let previousAccountId = "";

      if (recoveryCode) {
        const recovery = social.recoverIdentity(message.identity_key, recoveryCode);
        if (!recovery.ok) {
          sendError(client.ws, recovery.code, recovery.message);
          client.ws?.close(1008, "PARDEX account recovery rejected");
          return;
        }
        accountId = recovery.accountId;
        previousAccountId = recovery.previousAccountId || "";
        recovered = true;
        revokeAccountSessions(accountId, client);
      } else {
        accountId = social.resolveAccountId(message.identity_key);
      }

      if (!accountId) {
        sendError(client.ws, "INVALID_IDENTITY", "PARDEX cihaz kimliği geçersiz veya bu hesap başka bir cihaza taşındı.");
        client.ws?.close(1008, "Invalid PARDEX identity");
        return;
      }
      if (client.helloReceived && client.accountId && client.accountId !== accountId) {
        sendError(client.ws, "ACCOUNT_CHANGE_NOT_ALLOWED", "Açık bir PARDEX oturumunda hesap değiştirilemez.");
        return;
      }
      const resumed = recovered ? false : tryResumeClient(client, message.resume_token, accountId);
      client.helloReceived = true;
      if (client.helloTimer) {
        clearTimeout(client.helloTimer);
        client.helloTimer = null;
      }
      client.accountId = accountId;
      const existingAccount = social.getAccount(accountId);
      client.displayName = recovered && existingAccount
        ? existingAccount.display_name
        : safeName(message.display_name);
      client.presenceStatus = safePresence(message.presence_status || client.presenceStatus);
      social.ensureAccount(accountId, client.displayName);
      social.registerIdentity(accountId, message.identity_key);
      send(client.ws, {
        type: "welcome",
        user_id: client.userId,
        account_id: client.accountId,
        display_name: client.displayName,
        resume_token: client.resumeToken,
        resumed,
        recovered,
        recovery_enabled: social.hasRecoveryCode(client.accountId),
        social_enabled: true,
        room_invites_enabled: true,
        presence_enabled: true,
        friend_join_enabled: true,
      });
      syncClientNameToRoom(client);
      pushSocialState(client.accountId);
      pushRelatedSocialStates(client.accountId);
      if (recovered && previousAccountId && previousAccountId !== client.accountId) {
        pushRelatedSocialStates(previousAccountId);
      }
      break;
    }
    case "set_recovery_code": {
      if (!requireSocialAccount(client)) return;
      const result = social.setRecoveryCode(client.accountId, message.recovery_code);
      if (!result.ok) {
        sendError(client.ws, result.code, result.message);
        return;
      }
      send(client.ws, {
        type: "recovery_code_saved",
        recovery_enabled: true,
        message: result.message,
      });
      break;
    }
    case "get_social_state":
      if (requireSocialAccount(client)) pushSocialState(client.accountId);
      break;
    case "search_users":
      if (requireSocialAccount(client)) send(client.ws, {
        type: "user_search_results",
        query: String(message.query || ""),
        results: social.searchUsers(message.query, client.accountId, isAccountOnline),
      });
      break;
    case "set_presence":
      setPresenceStatus(client, message.presence);
      break;
    case "join_friend_room":
      joinFriendRoom(client, message.account_id);
      break;
    case "send_friend_request": {
      if (!requireSocialAccount(client)) return;
      const targetId = String(message.account_id || "");
      applySocialAction(client, social.sendFriendRequest(client.accountId, targetId), targetId);
      break;
    }
    case "accept_friend_request": {
      if (!requireSocialAccount(client)) return;
      const fromId = String(message.account_id || "");
      applySocialAction(client, social.acceptFriendRequest(client.accountId, fromId), fromId);
      break;
    }
    case "decline_friend_request": {
      if (!requireSocialAccount(client)) return;
      const fromId = String(message.account_id || "");
      applySocialAction(client, social.declineFriendRequest(client.accountId, fromId), fromId);
      break;
    }
    case "cancel_friend_request": {
      if (!requireSocialAccount(client)) return;
      const targetId = String(message.account_id || "");
      applySocialAction(client, social.cancelFriendRequest(client.accountId, targetId), targetId);
      break;
    }
    case "remove_friend": {
      if (!requireSocialAccount(client)) return;
      const targetId = String(message.account_id || "");
      applySocialAction(client, social.removeFriend(client.accountId, targetId), targetId);
      break;
    }
    case "send_room_invite":
      sendRoomInvite(client, message.account_id);
      break;
    case "accept_room_invite":
      respondToRoomInvite(client, message.invite_id, true);
      break;
    case "decline_room_invite":
      respondToRoomInvite(client, message.invite_id, false);
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
    case "launch_failed":
      reportGameLaunchFailed(client);
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
    const connectedClients = Array.from(clients.values()).filter((client) => client.ws).length;
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      ok: !shuttingDown,
      rooms: rooms.size,
      clients: connectedClients,
      recoverable_sessions: Math.max(0, clients.size - connectedClients),
      sessionGraceMs: SESSION_GRACE_MS,
      roomInviteTtlMs: ROOM_INVITE_TTL_MS,
      pendingRoomInvites: roomInvites.size,
      socialAccounts: Object.keys(social.data.accounts).length,
      socialDataPathConfigured: Boolean(SOCIAL_DATA_PATH),
      korsanGameServerAssigned: Boolean(KORSAN_GAME_SERVER_URL),
      voiceRelay: VOICE_RELAY_ENABLED,
      presence: true,
      friendRoomJoin: true,
      accountRecovery: true,
    }));
    return;
  }
  res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("PARDEX Online server\n");
});

const wss = new WebSocketServer({ server: httpServer, maxPayload: MAX_PAYLOAD_BYTES });

wss.on("connection", (ws) => {
  if (shuttingDown) {
    ws.close(1012, "Service restarting");
    return;
  }
  const userId = crypto.randomUUID();
  const resumeToken = createResumeToken();
  const client = {
    userId,
    accountId: "",
    resumeToken,
    displayName: "Pardus",
    roomCode: "",
    presenceStatus: "online",
    helloReceived: false,
    replaced: false,
    disconnectTimer: null,
    rateWindowStartedAt: Date.now(),
    rateMessageCount: 0,
    voiceRateWindowStartedAt: Date.now(),
    voiceRateMessageCount: 0,
    helloTimer: null,
    ws,
  };
  client.helloTimer = setTimeout(() => {
    client.helloTimer = null;
    if (!client.helloReceived && client.ws === ws) ws.close(1008, "PARDEX hello timeout");
  }, HELLO_TIMEOUT_MS);
  client.helloTimer.unref?.();
  clients.set(userId, client);
  resumeTokens.set(resumeToken, userId);
  ws.on("message", (raw) => handleMessage(client, raw));
  ws.on("close", () => {
    if (client.helloTimer) {
      clearTimeout(client.helloTimer);
      client.helloTimer = null;
    }
    detachClient(client, ws);
  });
  ws.on("error", () => {});
});

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`PARDEX Online shutting down (${signal})`);
  for (const invite of [...roomInvites.values()]) closeRoomInvite(invite, "server_restarting");
  for (const client of clients.values()) {
    if (client.disconnectTimer) clearTimeout(client.disconnectTimer);
    client.ws?.close(1012, "PARDEX Online restarting");
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
