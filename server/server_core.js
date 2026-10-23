const http = require("http");
const path = require("path");
const fs = require("fs");
const { WebSocketServer, WebSocket } = require("ws");
const crypto = require("crypto");
const { SocialStore } = require("./social_store");
const { userSummary } = require("./user_admin");

const PORT = Number(process.env.PORT || 8765);
const HOST = process.env.HOST || "0.0.0.0";
// One address per dedicated Korsan server process; each process runs one
// table, so several addresses (comma-separated) allow several tables at once.
const KORSAN_GAME_SERVER_URLS = String(process.env.KORSAN_GAME_SERVER_URLS || process.env.KORSAN_GAME_SERVER_URL || "")
  .split(",").map((url) => url.trim()).filter(Boolean);
const GAME_SERVER_TOKEN = String(process.env.PARDEX_GAME_SERVER_TOKEN || "").trim();
const SESSION_GRACE_MS = Math.max(1000, Number(process.env.SESSION_GRACE_MS || 30_000));
const ROOM_INVITE_TTL_MS = Math.max(15_000, Number(process.env.ROOM_INVITE_TTL_MS || 60_000));
const HELLO_TIMEOUT_MS = Math.max(500, Number(process.env.HELLO_TIMEOUT_MS || 10_000));
const GAME_LAUNCH_TICKET_TTL_MS = Math.max(
  1000,
  Number(process.env.GAME_LAUNCH_TICKET_TTL_MS || 120_000)
);
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
// One-to-one voice calls between friends (like Steam). Audio frames are
// relayed by this server; the ring stops after CALL_RING_TIMEOUT_MS.
const CALL_RING_TIMEOUT_MS = Math.max(1000, Number(process.env.CALL_RING_TIMEOUT_MS || 30_000));
const PRESENCE_VALUES = new Set(["online", "away", "busy"]);
const ROOM_STATES = new Set(["lobby", "launching", "in_game", "ended", "closed"]);

const clients = new Map();
const rooms = new Map();
const calls = new Map();
const callByUser = new Map();
const resumeTokens = new Map();
const roomInvites = new Map();
const gameLaunchTickets = new Map();
// PARDEX launcher <-> server protocol. Bump PROTOCOL_VERSION when the server
// gains requests a client may use; raise MIN_CLIENT_PROTOCOL only when old
// clients can no longer work at all (they then get a clear "update" error).
const PROTOCOL_VERSION = 4;
const MIN_CLIENT_PROTOCOL = 0;
// Network protocol of each game's dedicated server, reported at start-up
// (game_server_hello). Games compare theirs before hosting/joining a table.
const gameServerProtocols = new Map();
// Game session tokens: PARDEX hands one to the game it launches so the game
// itself can host a table or join one by code (token hash -> owner session).
const gameSessions = new Map();
const GAME_SESSION_TTL_MS = 12 * 60 * 60 * 1000;
// Deployment-specific checks (production_server.js) plug in here.
const hooks = {};
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

function safeRoomState(value) {
  const normalized = String(value || "lobby").trim().toLowerCase();
  return ROOM_STATES.has(normalized) ? normalized : "lobby";
}

function createResumeToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function gameLaunchTicketHash(ticket) {
  return crypto.createHash("sha256").update(String(ticket || ""), "utf8").digest("hex");
}

function createGameLaunchTicket(room, member) {
  const ticket = crypto.randomBytes(32).toString("base64url");
  const expiresAt = Date.now() + GAME_LAUNCH_TICKET_TTL_MS;
  gameLaunchTickets.set(gameLaunchTicketHash(ticket), {
    matchId: room.matchId,
    roomCode: room.code,
    gameId: room.gameId,
    userId: member.userId,
    accountId: member.accountId || "",
    expiresAt,
  });
  return { ticket, expiresAt };
}

function clearGameLaunchTicketsForMatch(matchId) {
  const normalized = String(matchId || "").trim();
  if (!normalized) return;
  for (const [ticketHash, record] of gameLaunchTickets.entries()) {
    if (record.matchId === normalized) gameLaunchTickets.delete(ticketHash);
  }
}

function pruneGameLaunchTickets(now = Date.now()) {
  for (const [ticketHash, record] of gameLaunchTickets.entries()) {
    if (now >= record.expiresAt) gameLaunchTickets.delete(ticketHash);
  }
}

function gameServerUrls(gameId) {
  return gameId === "korsanlar" ? KORSAN_GAME_SERVER_URLS : [];
}

function gameServerUrl(gameId, room = null) {
  const urls = gameServerUrls(gameId);
  return urls[room?.serverSlot || 0] || urls[0] || "";
}

// Lowest game server slot that no launching or running table uses; -1 when
// every server is busy.
function freeGameServerSlot(gameId, excludeCode = "") {
  const busy = new Set();
  for (const room of rooms.values()) {
    if (room.code === excludeCode || room.gameId !== gameId) continue;
    if (roomIsLaunching(room) || roomIsInGame(room)) busy.add(room.serverSlot || 0);
  }
  const count = gameServerUrls(gameId).length;
  for (let slot = 0; slot < count; slot += 1) {
    if (busy.has(slot) || hooks.slotUnavailable?.(gameId, slot)) continue;
    return slot;
  }
  return -1;
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

function roomState(room) {
  if (!room) return "closed";
  if (room.state) return safeRoomState(room.state);
  return room.launching ? "launching" : "lobby";
}

function roomIsLobby(room) {
  return roomState(room) === "lobby";
}

function roomIsLaunching(room) {
  return roomState(room) === "launching";
}

function roomIsInGame(room) {
  return roomState(room) === "in_game";
}

// Quick-play rooms (PARDEX "Oyna") start the match at once and keep taking
// players while the game's own lobby is open, i.e. until the dedicated game
// server reports that the match has begun.
function roomAcceptsPlayers(room) {
  if (!room) return false;
  if (roomIsLobby(room)) return true;
  return Boolean(room.quickPlay)
    && !room.matchStarted
    && (roomIsLaunching(room) || roomIsInGame(room));
}

function resetMemberForLobby(member) {
  member.ready = false;
  member.gameState = "lobby";
  member.gameConnectedAt = 0;
}

function resetRoomToLobby(room) {
  clearGameLaunchTicketsForMatch(room.matchId);
  room.state = "lobby";
  room.matchId = "";
  room.matchStarted = false;
  room.launchStartedAt = 0;
  room.startedAt = 0;
  room.endedAt = 0;
  for (const member of room.members) resetMemberForLobby(member);
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
      room_state: "",
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
  let chosenRank = -1;
  const stateRank = { lobby: 1, ended: 2, launching: 3, in_game: 4 };
  for (const client of connected) {
    if (!client.roomCode) continue;
    const room = rooms.get(client.roomCode);
    if (!room) continue;
    if (!room.members.some((member) => member.userId === client.userId)) continue;
    const rank = stateRank[roomState(room)] || 0;
    if (!chosenRoom || rank > chosenRank) {
      chosenRoom = room;
      chosenRank = rank;
    }
  }

  if (!chosenRoom) {
    return {
      presence: manualPresence,
      in_room: false,
      in_game: false,
      room_state: "",
      game_id: "",
      game_name: "",
      room_joinable: false,
      room_member_count: 0,
      room_max_players: 0,
    };
  }

  const state = roomState(chosenRoom);
  return {
    presence: state === "in_game" ? "in_game" : manualPresence,
    in_room: true,
    in_game: state === "in_game",
    room_state: state,
    game_id: chosenRoom.gameId,
    game_name: gameDisplayName(chosenRoom.gameId),
    room_joinable: roomAcceptsPlayers(chosenRoom) && chosenRoom.members.length < chosenRoom.maxPlayers,
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
  state.friends = (state.friends || []).map((profile) => ({
    ...enrichFriendProfile(profile),
    ...social.chatSummary(accountId, profile.account_id),
  })).sort((a, b) => {
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

function memberConnectionState(member) {
  const client = clients.get(member.userId);
  if (client?.ws?.readyState === WebSocket.OPEN) return "online";
  if (client && client.helloReceived) return "reconnecting";
  return "offline";
}

function roomPayload(room) {
  const state = roomState(room);
  return {
    code: room.code,
    game_id: room.gameId,
    game_server_url: gameServerUrl(room.gameId, room),
    host_id: room.hostId,
    max_players: room.maxPlayers,
    state,
    match_id: room.matchId || "",
    quick_play: Boolean(room.quickPlay),
    match_started: Boolean(room.matchStarted),
    joinable: roomAcceptsPlayers(room),
    launch_started_at: room.launchStartedAt || 0,
    started_at: room.startedAt || 0,
    ended_at: room.endedAt || 0,
    launching: state === "launching",
    in_game: state === "in_game",
    ended: state === "ended",
    members: room.members.map((member) => ({
      user_id: member.userId,
      account_id: member.accountId || "",
      display_name: member.displayName,
      ready: member.ready,
      voice_muted: Boolean(member.voiceMuted),
      game_state: member.gameState || "lobby",
      game_connected_at: member.gameConnectedAt || 0,
      connection_state: memberConnectionState(member),
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

function sendRoomLifecycleEvent(room, type, extra = {}) {
  const payload = { type, room: roomPayload(room), ...extra };
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
  if (!roomAcceptsPlayers(room)) {
    sendError(client.ws, "ROOM_IN_GAME", "Maç başladı; artık davet gönderilemez.");
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
  if (!roomAcceptsPlayers(room)) {
    closeRoomInvite(invite, "room_in_game");
    sendError(client.ws, "ROOM_IN_GAME", "Bu oda artık lobi durumunda değil.");
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
  if (!roomAcceptsPlayers(room)) {
    sendError(client.ws, "ROOM_IN_GAME", "Arkadaşının maçı başladı; bitince katılabilirsin.");
    return;
  }
  if (room.members.length >= room.maxPlayers) {
    sendError(client.ws, "ROOM_FULL", "Arkadaşının odası dolu.");
    return;
  }

  joinRoom(client, room.code);
  sendNotice(client.ws, "FRIEND_ROOM_JOINED", `${social.getAccount(targetId)?.display_name || "Arkadaşının"} odasına katıldın.`);
}

function abortRoomLaunch(room, failedUserId = "", reason = "launch_failed") {
  if (!room || !roomIsLaunching(room)) return;
  resetRoomToLobby(room);
  broadcastRoom(room);
  pushRoomPresence(room);
  sendRoomLifecycleEvent(room, "game_launch_aborted", {
    failed_user_id: failedUserId,
    reason: String(reason || "launch_failed").slice(0, 96),
  });
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

  const previousState = roomState(room);
  room.members = room.members.filter((member) => member.userId !== userId);
  if (room.members.length === 0) {
    clearGameLaunchTicketsForMatch(room.matchId);
    room.state = "closed";
    rooms.delete(room.code);
    cancelInvitesForRoom(room.code, "room_closed");
  } else {
    if (room.hostId === userId) room.hostId = room.members[0].userId;
    if (previousState === "launching" && !room.quickPlay) {
      resetRoomToLobby(room);
      sendRoomLifecycleEvent(room, "game_launch_aborted", {
        failed_user_id: userId,
        reason: "member_left",
      });
    }
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
  // A dropped connection ends the call for both sides.
  const call = activeCallOf(client);
  if (call) endCall(call, "disconnected");
  if (!client.helloReceived) {
    clients.delete(client.userId);
    resumeTokens.delete(client.resumeToken);
    return;
  }
  if (client.disconnectTimer) clearTimeout(client.disconnectTimer);
  client.disconnectTimer = setTimeout(() => expireDisconnectedClient(client), SESSION_GRACE_MS);
  client.disconnectTimer.unref?.();
  if (client.roomCode) {
    const room = rooms.get(client.roomCode);
    if (room) broadcastRoom(room);
  }
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
  client.gameWs = existing.gameWs || null;
  client.helloReceived = true;
  clients.set(client.userId, client);
  resumeTokens.set(client.resumeToken, client.userId);

  if (previousSocket && previousSocket !== client.ws) previousSocket.close(4001, "PARDEX session resumed elsewhere");
  return true;
}

function joinRoom(client, code, replyWs = client.ws) {
  const normalized = String(code || "").trim().toUpperCase();
  const room = rooms.get(normalized);
  if (!room) return sendError(replyWs, "ROOM_NOT_FOUND", "Bu kodla açık bir masa yok.");
  if (!roomAcceptsPlayers(room)) return sendError(replyWs, "ROOM_IN_GAME", "Bu masada oyun başladı; artık katılınamaz.");
  if (client.roomCode === normalized) {
    broadcastRoom(room);
    return;
  }
  if (room.members.length >= room.maxPlayers) return sendError(replyWs, "ROOM_FULL", "Masa dolu.");

  const oldAccountId = client.accountId;
  leaveCurrentRoom(client.userId, false);
  const lateJoin = !roomIsLobby(room);
  const member = {
    userId: client.userId,
    accountId: client.accountId,
    displayName: client.displayName,
    ready: lateJoin,
    voiceMuted: false,
    gameState: lateJoin ? "launching" : "lobby",
    gameConnectedAt: 0,
  };
  room.members.push(member);
  client.roomCode = room.code;
  broadcastRoom(room);
  pushRelatedSocialStates(oldAccountId);
  pushRoomPresence(room);
  // A quick-play match is already running: hand the newcomer a launch ticket
  // so their game opens straight into the same in-game lobby.
  if (lateJoin) sendGameStart(room, member, client.userId);
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
    state: "lobby",
    matchId: "",
    launchStartedAt: 0,
    startedAt: 0,
    endedAt: 0,
    members: [{
      userId: client.userId,
      accountId: client.accountId,
      displayName: client.displayName,
      ready: false,
      voiceMuted: false,
      gameState: "lobby",
      gameConnectedAt: 0,
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
  if (!roomIsLobby(room)) return sendError(client.ws, "ROOM_NOT_IN_LOBBY", "Oyun yalnız lobi durumundayken başlatılabilir.");
  if (room.members.length < 2) return sendError(client.ws, "NOT_ENOUGH_PLAYERS", "Oyunu başlatmak için en az 2 oyuncu gerekli.");
  if (!room.members.every((member) => member.ready)) return sendError(client.ws, "PLAYERS_NOT_READY", "Tüm oyuncular hazır olmalı.");
  if (!gameServerUrl(room.gameId)) return sendError(client.ws, "GAME_SERVER_UNAVAILABLE", "Bu oyun için PARDEX oyun sunucusu hazır değil.");
  launchRoomMatch(room, client);
}

function launchRoomMatch(room, client) {
  pruneGameLaunchTickets();
  room.state = "launching";
  room.serverSlot = Math.max(0, freeGameServerSlot(room.gameId, room.code));
  room.matchId = crypto.randomUUID();
  room.launchStartedAt = Date.now();
  room.startedAt = 0;
  room.endedAt = 0;
  for (const member of room.members) {
    member.gameState = "launching";
    member.gameConnectedAt = 0;
  }
  if (!room.quickPlay) cancelInvitesForRoom(room.code, "room_in_game");
  broadcastRoom(room);
  pushRoomPresence(room);
  for (const member of room.members) sendGameStart(room, member, client.userId);
}

function sendGameStart(room, member, startedBy) {
  const memberClient = clients.get(member.userId);
  if (!memberClient) return;
  // The game is already open and linked: hand it the ticket directly.
  // Otherwise PARDEX receives game_start and launches the game.
  const gameOpen = memberClient.gameWs?.readyState === WebSocket.OPEN;
  const target = gameOpen ? memberClient.gameWs : memberClient.ws;
  if (!target || target.readyState !== WebSocket.OPEN) return;
  const launch = createGameLaunchTicket(room, member);
  send(target, {
    type: gameOpen ? "match_ticket" : "game_start",
    user_id: member.userId,
    display_name: member.displayName,
    role: room.hostId === member.userId ? "host" : "client",
    game_id: room.gameId,
    match_id: room.matchId,
    room: roomPayload(room),
    started_by: startedBy,
    started_at: room.launchStartedAt,
    launch_ticket: launch.ticket,
    launch_ticket_expires_at: launch.expiresAt,
  });
}

// PARDEX "Oyna": no party step. The player gets a fresh quick-play room whose
// match starts at once, so the game opens directly in its own lobby. Friends
// join through invites or "Katıl" while that lobby is open.
function playGame(client, message, replyWs = client.ws) {
  if (!requireSocialAccount(client)) return;
  const gameId = String(message.game_id || "korsanlar").slice(0, 32);
  if (!gameServerUrl(gameId)) {
    return sendError(replyWs, "GAME_SERVER_UNAVAILABLE", "Bu oyun için PARDEX oyun sunucusu hazır değil.");
  }
  if (hooks.beforePlayGame && hooks.beforePlayGame(client, gameId, replyWs)) return;
  // Already in a running match of this game (e.g. the game was closed or
  // crashed): a fresh ticket reopens it in the same lobby, or takes the seat
  // back from the bot once the match has started.
  const current = client.roomCode ? rooms.get(client.roomCode) : null;
  if (
    current && current.quickPlay && current.gameId === gameId
    && (roomIsLaunching(current) || roomIsInGame(current))
  ) {
    const member = current.members.find((item) => item.userId === client.userId);
    if (member) {
      sendGameStart(current, member, client.userId);
      return;
    }
  }

  leaveCurrentRoom(client.userId, false);
  const room = {
    code: roomCode(),
    gameId,
    hostId: client.userId,
    maxPlayers: 4,
    quickPlay: true,
    matchStarted: false,
    state: "lobby",
    matchId: "",
    launchStartedAt: 0,
    startedAt: 0,
    endedAt: 0,
    members: [{
      userId: client.userId,
      accountId: client.accountId,
      displayName: client.displayName,
      ready: true,
      voiceMuted: false,
      gameState: "lobby",
      gameConnectedAt: 0,
    }],
  };
  rooms.set(room.code, room);
  client.roomCode = room.code;
  launchRoomMatch(room, client);
}

function validateMatch(room, message) {
  const matchId = String(message.match_id || "").trim();
  return Boolean(matchId && room.matchId && matchId === room.matchId);
}

function markMemberGameConnected(room, member) {
  member.gameState = "in_game";
  if (!member.gameConnectedAt) member.gameConnectedAt = Date.now();

  if (roomIsLaunching(room) && room.members.every((item) => item.gameState === "in_game")) {
    clearGameLaunchTicketsForMatch(room.matchId);
    room.state = "in_game";
    room.startedAt = Date.now();
    broadcastRoom(room);
    pushRoomPresence(room);
    sendRoomLifecycleEvent(room, "game_started", {
      match_id: room.matchId,
      started_at: room.startedAt,
    });
    return;
  }

  broadcastRoom(room);
  pushRoomPresence(room);
}

function handleGameHello(client, message) {
  const matchId = String(message.match_id || "").trim();
  const ticket = String(message.launch_ticket || "").trim();
  const requestedGameId = String(message.game_id || "").trim();
  if (!matchId || !ticket) {
    sendError(client.ws, "GAME_TICKET_REQUIRED", "Oyun bağlantısı için geçerli bir PARDEX ticket gerekli.");
    return;
  }

  const ticketHash = gameLaunchTicketHash(ticket);
  const record = gameLaunchTickets.get(ticketHash);
  if (!record) {
    sendError(client.ws, "GAME_TICKET_INVALID", "PARDEX oyun ticket'ı geçersiz veya daha önce kullanılmış.");
    return;
  }
  if (Date.now() >= record.expiresAt) {
    gameLaunchTickets.delete(ticketHash);
    sendError(client.ws, "GAME_TICKET_EXPIRED", "PARDEX oyun ticket'ının süresi doldu.");
    return;
  }
  if (record.matchId !== matchId) {
    sendError(client.ws, "MATCH_MISMATCH", "Oyun oturumu kimliği ticket ile eşleşmiyor.");
    return;
  }
  if (requestedGameId && requestedGameId !== record.gameId) {
    sendError(client.ws, "GAME_MISMATCH", "Oyun kimliği ticket ile eşleşmiyor.");
    return;
  }

  const room = rooms.get(record.roomCode);
  if (!room || (!roomIsLaunching(room) && !roomIsInGame(room))) {
    gameLaunchTickets.delete(ticketHash);
    sendError(client.ws, "GAME_SESSION_CLOSED", "PARDEX oyun oturumu artık aktif değil.");
    return;
  }
  if (room.matchId !== record.matchId || room.gameId !== record.gameId) {
    gameLaunchTickets.delete(ticketHash);
    sendError(client.ws, "MATCH_MISMATCH", "PARDEX oyun oturumu artık geçerli değil.");
    return;
  }

  const member = room.members.find((item) =>
    item.userId === record.userId
    && (!record.accountId || item.accountId === record.accountId)
  );
  if (!member) {
    gameLaunchTickets.delete(ticketHash);
    sendError(client.ws, "GAME_MEMBER_NOT_FOUND", "Bu ticket artık oda üyesiyle eşleşmiyor.");
    return;
  }

  gameLaunchTickets.delete(ticketHash);
  if (client.helloTimer) {
    clearTimeout(client.helloTimer);
    client.helloTimer = null;
  }
  markMemberGameConnected(room, member);
  send(client.ws, {
    type: "game_hello_ok",
    game_id: room.gameId,
    match_id: room.matchId,
    room_code: room.code,
    user_id: member.userId,
    game_connected_at: member.gameConnectedAt,
  });
}

function reportGameConnected(client, _message) {
  sendError(
    client.ws,
    "GAME_TICKET_REQUIRED",
    "game_connected artık launcher oturumundan kabul edilmiyor; oyun secure ticket ile game_hello göndermeli."
  );
}

function reportGameLaunchFailed(client, message) {
  if (!client.roomCode) return;
  const room = rooms.get(client.roomCode);
  if (!room || (!roomIsLaunching(room) && !(room.quickPlay && roomIsInGame(room)))) return;
  if (message.match_id && !validateMatch(room, message)) return;
  const member = room.members.find((item) => item.userId === client.userId);
  if (!member) return;
  if (room.quickPlay) {
    // Only this player's game failed to open; the others keep their lobby.
    leaveCurrentRoom(client.userId);
    return;
  }
  abortRoomLaunch(room, client.userId, message.reason || "launch_failed");
}

function reportGameEnded(client, message) {
  if (!client.roomCode) return sendError(client.ws, "NO_ROOM", "Aktif oyun odası bulunamadı.");
  const room = rooms.get(client.roomCode);
  if (!room) return sendError(client.ws, "ROOM_NOT_FOUND", "Oda bulunamadı.");
  if (room.hostId !== client.userId) return sendError(client.ws, "NOT_HOST", "Oyunu yalnız oda kurucusu sonlandırabilir.");
  if (!roomIsLaunching(room) && !roomIsInGame(room)) {
    return sendError(client.ws, "GAME_NOT_ACTIVE", "Bu odada aktif oyun yok.");
  }
  if (!validateMatch(room, message)) {
    return sendError(client.ws, "MATCH_MISMATCH", "Oyun oturumu kimliği artık geçerli değil.");
  }

  clearGameLaunchTicketsForMatch(room.matchId);
  room.state = "ended";
  room.endedAt = Date.now();
  for (const member of room.members) {
    member.gameState = "ended";
    member.ready = false;
  }
  broadcastRoom(room);
  pushRoomPresence(room);
  sendRoomLifecycleEvent(room, "game_ended", {
    match_id: room.matchId,
    ended_at: room.endedAt,
    result: typeof message.result === "object" && message.result !== null ? message.result : {},
  });
}

function returnRoomToLobby(client) {
  if (!client.roomCode) return sendError(client.ws, "NO_ROOM", "Aktif oda bulunamadı.");
  const room = rooms.get(client.roomCode);
  if (!room) return sendError(client.ws, "ROOM_NOT_FOUND", "Oda bulunamadı.");
  if (room.hostId !== client.userId) return sendError(client.ws, "NOT_HOST", "Lobiye yalnız oda kurucusu döndürebilir.");
  if (roomState(room) !== "ended") {
    return sendError(client.ws, "ROOM_NOT_ENDED", "Oda yalnız oyun bittikten sonra lobiye döndürülebilir.");
  }
  resetRoomToLobby(room);
  broadcastRoom(room);
  pushRoomPresence(room);
  sendRoomLifecycleEvent(room, "room_returned_to_lobby", { returned_by: client.userId });
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

// ------------------------------------------------------------------ voice calls

function callPayload(call, forUserId) {
  const outgoing = call.caller.userId === forUserId;
  const peer = outgoing ? call.callee : call.caller;
  return {
    id: call.id,
    state: call.state,
    outgoing,
    peer_account_id: peer.accountId,
    peer_name: peer.displayName,
    started_at: call.startedAt,
  };
}

function sendCallState(call) {
  for (const party of [call.caller, call.callee]) {
    const client = clients.get(party.userId);
    if (client?.ws) send(client.ws, { type: "call_state", call: callPayload(call, party.userId) });
  }
}

function endCall(call, reason) {
  if (!calls.has(call.id)) return;
  calls.delete(call.id);
  clearTimeout(call.ringTimer);
  for (const party of [call.caller, call.callee]) {
    if (callByUser.get(party.userId) === call.id) callByUser.delete(party.userId);
    const client = clients.get(party.userId);
    if (client?.ws) send(client.ws, { type: "call_ended", call_id: call.id, reason });
  }
}

function activeCallOf(client) {
  const call = calls.get(callByUser.get(client.userId));
  return call || null;
}

function startCall(client, message) {
  if (!requireSocialAccount(client)) return;
  const targetId = String(message.account_id || "").trim();
  if (!targetId || targetId === client.accountId) return sendError(client.ws, "CALL_INVALID", "Bu kişi aranamaz.");
  if (social.relationshipBetween(client.accountId, targetId) !== "friend") {
    return sendError(client.ws, "NOT_FRIENDS", "Yalnız arkadaşlarını arayabilirsin.");
  }
  if (activeCallOf(client)) return sendError(client.ws, "CALL_BUSY", "Zaten bir aramadasın.");
  const target = clientsForAccount(targetId).at(-1);
  if (!target) return sendError(client.ws, "CALL_OFFLINE", "Arkadaşın şu an çevrimiçi değil.");
  if (activeCallOf(target)) return sendError(client.ws, "CALL_BUSY", "Arkadaşın şu an başka bir aramada.");
  const call = {
    id: crypto.randomUUID(),
    state: "ringing",
    startedAt: 0,
    caller: { userId: client.userId, accountId: client.accountId, displayName: client.displayName },
    callee: { userId: target.userId, accountId: target.accountId, displayName: target.displayName },
  };
  call.ringTimer = setTimeout(() => endCall(call, "missed"), CALL_RING_TIMEOUT_MS);
  call.ringTimer.unref?.();
  calls.set(call.id, call);
  callByUser.set(client.userId, call.id);
  callByUser.set(target.userId, call.id);
  sendCallState(call);
}

function answerCall(client, message, accept) {
  const call = activeCallOf(client);
  if (!call || call.id !== String(message.call_id || "") || call.callee.userId !== client.userId || call.state !== "ringing") {
    return sendError(client.ws, "CALL_NOT_FOUND", "Arama artık geçerli değil.");
  }
  if (!accept) return endCall(call, "declined");
  clearTimeout(call.ringTimer);
  call.state = "active";
  call.startedAt = Date.now();
  sendCallState(call);
}

function hangUp(client) {
  const call = activeCallOf(client);
  if (!call) return;
  endCall(call, call.state === "ringing" && call.caller.userId === client.userId ? "cancelled" : "ended");
}

function callPeer(call, client) {
  const peer = call.caller.userId === client.userId ? call.callee : call.caller;
  return clients.get(peer.userId);
}

function relayCallFrame(client, message) {
  const call = activeCallOf(client);
  if (!call || call.state !== "active") return;
  const data = String(message.data || "");
  if (!data || data.length > MAX_VOICE_BASE64_CHARS) return;
  const sequence = Number.isFinite(Number(message.seq)) ? Math.max(0, Math.floor(Number(message.seq))) : 0;
  const peer = callPeer(call, client);
  if (peer?.ws) sendVoice(peer.ws, { type: "call_frame", seq: sequence, data });
}

function relayCallMute(client, muted) {
  const call = activeCallOf(client);
  if (!call) return;
  const peer = callPeer(call, client);
  if (peer?.ws) send(peer.ws, { type: "call_peer_muted", muted: Boolean(muted) });
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
  // Unfriending or blocking ends a call between the two at once.
  if (social.relationshipBetween(client.accountId, otherAccountId) !== "friend") {
    for (const call of [...calls.values()]) {
      const parties = [call.caller.accountId, call.callee.accountId];
      if (parties.includes(client.accountId) && parties.includes(otherAccountId)) endCall(call, "ended");
    }
  }
}

function issueGameSession(client, message) {
  if (!requireSocialAccount(client)) return;
  const gameId = String(message.game_id || "korsanlar").slice(0, 32);
  const now = Date.now();
  for (const [hash, record] of gameSessions.entries()) {
    if (now >= record.expiresAt || record.userId === client.userId) gameSessions.delete(hash);
  }
  const token = crypto.randomBytes(32).toString("base64url");
  gameSessions.set(gameLaunchTicketHash(token), {
    userId: client.userId,
    accountId: client.accountId,
    gameId,
    expiresAt: now + GAME_SESSION_TTL_MS,
  });
  send(client.ws, { type: "game_session", game_id: gameId, token });
}

function gameLinkOwner(link) {
  const owner = clients.get(link.gameLinkOf || "");
  if (!owner || owner.accountId !== link.gameLinkAccount) return null;
  return owner;
}

// Messages from a game opened by PARDEX. The connection is not a PARDEX
// session of its own; it acts for the PARDEX session that issued its token.
function handleGameLinkMessage(link, message) {
  if (message.type === "game_link") {
    const record = gameSessions.get(gameLaunchTicketHash(String(message.token || "").trim()));
    const owner = record && Date.now() < record.expiresAt ? clients.get(record.userId) : null;
    if (!owner || owner.accountId !== record.accountId) {
      sendError(link.ws, "GAME_SESSION_INVALID", "PARDEX oturumu bulunamadı. Oyunu PARDEX'ten yeniden aç.");
      return;
    }
    if (link.helloTimer) {
      clearTimeout(link.helloTimer);
      link.helloTimer = null;
    }
    clients.delete(link.userId);
    resumeTokens.delete(link.resumeToken);
    link.gameLinkOf = owner.userId;
    link.gameLinkAccount = owner.accountId;
    link.gameId = record.gameId;
    link.gameProtocol = Number(message.game_protocol || 0);
    owner.gameWs = link.ws;
    send(link.ws, {
      type: "game_link_ok",
      game_id: record.gameId,
      user_id: owner.userId,
      display_name: owner.displayName,
    });
    return;
  }
  const owner = gameLinkOwner(link);
  if (!owner) {
    sendError(link.ws, "GAME_SESSION_INVALID", "PARDEX bağlantısı kapandı. PARDEX'i açık tut ve oyunu yeniden başlat.");
    return;
  }
  const serverProtocol = gameServerProtocols.get(link.gameId);
  if (
    (message.type === "host_match" || message.type === "join_match")
    && serverProtocol !== undefined && link.gameProtocol && serverProtocol !== link.gameProtocol
  ) {
    const older = link.gameProtocol < serverProtocol ? "Senin oyunun" : "Sunucudaki oyun";
    sendError(
      link.ws,
      "GAME_VERSION_MISMATCH",
      `${older} eski sürüm (oyun ${link.gameProtocol}, sunucu ${serverProtocol}). Korsanların Hazinesi'ni güncelleyip yeniden dene.`
    );
    return;
  }
  if (message.type === "host_match") {
    playGame(owner, { game_id: link.gameId }, link.ws);
  } else if (message.type === "join_match") {
    const room = rooms.get(String(message.code || "").trim().toUpperCase());
    if (room && room.gameId !== link.gameId) {
      sendError(link.ws, "ROOM_NOT_FOUND", "Bu kod başka bir oyunun masası.");
      return;
    }
    if (room && room.members.some((member) => member.userId === owner.userId)) {
      playGame(owner, { game_id: link.gameId }, link.ws);
      return;
    }
    joinRoom(owner, message.code, link.ws);
  } else if (message.type === "leave_match") {
    leaveCurrentRoom(owner.userId);
  } else if (message.type !== "ping") {
    sendError(link.ws, "UNKNOWN_GAME_MESSAGE", "Bilinmeyen oyun isteği.");
  }
}

// ------------------------------------------------------------------ bug reports

const BUG_REPORT_DIR = path.join(path.dirname(SOCIAL_DATA_PATH), "bug-reports");
const MAX_BUG_REPORTS = 200;

// "Sorun bildir" from the launcher: one JSON file per report next to the
// social data (shown in the host panel), at most one per minute per session.
function saveBugReport(client, message) {
  if (!requireSocialAccount(client)) return;
  const now = Date.now();
  if (client.lastBugReportAt && now - client.lastBugReportAt < 60_000) {
    return sendError(client.ws, "BUG_REPORT_RATE_LIMIT", "Bir dakika içinde yalnız bir rapor gönderebilirsin.");
  }
  client.lastBugReportAt = now;
  const report = {
    at: now,
    account_id: client.accountId,
    display_name: client.displayName,
    text: String(message.text || "").slice(0, 500),
    version: String(message.version || "").slice(0, 64),
    os: String(message.os || "").slice(0, 128),
    log: String(message.log || "").slice(-8_000),
  };
  try {
    fs.mkdirSync(BUG_REPORT_DIR, { recursive: true });
    fs.writeFileSync(path.join(BUG_REPORT_DIR, `${now}-${client.accountId}.json`), JSON.stringify(report, null, 2));
    const files = fs.readdirSync(BUG_REPORT_DIR).filter((name) => name.endsWith(".json")).sort();
    for (const name of files.slice(0, Math.max(0, files.length - MAX_BUG_REPORTS))) fs.rmSync(path.join(BUG_REPORT_DIR, name));
    sendNotice(client.ws, "BUG_REPORT_SAVED", "Sorun raporun sunucu yöneticisine iletildi.");
  } catch (error) {
    console.error("PARDEX bug report save failed:", error.message);
    sendError(client.ws, "BUG_REPORT_FAILED", "Rapor kaydedilemedi.");
  }
}

// ------------------------------------------------------------------ chat

const CHAT_RATE_WINDOW_MS = 10_000;
const CHAT_RATE_LIMIT = 12;

function allowChat(client) {
  const now = Date.now();
  if (!client.chatWindowStartedAt || now - client.chatWindowStartedAt > CHAT_RATE_WINDOW_MS) {
    client.chatWindowStartedAt = now;
    client.chatCount = 0;
  }
  client.chatCount += 1;
  return client.chatCount <= CHAT_RATE_LIMIT;
}

function sendChat(client, message) {
  if (!requireSocialAccount(client)) return;
  const targetId = String(message.account_id || "").trim();
  if (!allowChat(client)) {
    sendError(client.ws, "CHAT_RATE_LIMIT", "Çok hızlı mesaj gönderiyorsun; biraz bekle.");
    return;
  }
  const result = social.sendChatMessage(client.accountId, targetId, message.text);
  if (!result.ok) return sendError(client.ws, result.code, result.message);
  const clientId = String(message.client_id || "").slice(0, 64);
  for (const session of clientsForAccount(client.accountId)) {
    send(session.ws, { type: "chat_message", with: targetId, message: result.message, client_id: clientId });
  }
  for (const session of clientsForAccount(targetId)) {
    send(session.ws, { type: "chat_message", with: client.accountId, message: result.message });
  }
  pushSocialState(client.accountId);
  pushSocialState(targetId);
}

function sendChatHistory(client, message) {
  if (!requireSocialAccount(client)) return;
  const targetId = String(message.account_id || "").trim();
  if (social.relationshipBetween(client.accountId, targetId) !== "friend") {
    return sendError(client.ws, "NOT_FRIENDS", "Yalnız arkadaşlarınla mesajlaşabilirsin.");
  }
  send(client.ws, { type: "chat_history", with: targetId, messages: social.chatHistory(client.accountId, targetId) });
}

function markChatRead(client, message) {
  if (!requireSocialAccount(client)) return;
  if (social.markChatRead(client.accountId, String(message.account_id || "").trim())) {
    pushSocialState(client.accountId);
  }
}

function secretMatches(expected, supplied) {
  const digest = (value) => crypto.createHash("sha256").update(String(value || "")).digest();
  return Boolean(supplied) && crypto.timingSafeEqual(digest(expected), digest(supplied));
}

// The dedicated game server announces its network protocol at start-up.
function handleGameServerHello(client, message) {
  if (!GAME_SERVER_TOKEN || !secretMatches(GAME_SERVER_TOKEN, message.server_token)) {
    sendError(client.ws, "GAME_SERVER_UNAUTHORIZED", "Oyun sunucusu doğrulanamadı.");
    return;
  }
  const gameId = String(message.game_id || "").trim().slice(0, 32);
  const protocol = Number(message.game_protocol || 0);
  if (gameId && protocol > 0) gameServerProtocols.set(gameId, protocol);
  if (client.helloTimer) {
    clearTimeout(client.helloTimer);
    client.helloTimer = null;
  }
  send(client.ws, { type: "game_server_hello_ok", game_id: gameId, protocol_version: PROTOCOL_VERSION });
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
  if (message.type === "call_frame") {
    if (client.helloReceived && allowVoiceFrame(client)) relayCallFrame(client, message);
    return;
  }
  if (!allowMessage(client)) return;

  if (message.type === "game_hello") {
    handleGameHello(client, message);
    return;
  }
  if (message.type === "game_server_hello") {
    handleGameServerHello(client, message);
    return;
  }
  if (message.type === "game_link" || client.gameLinkOf) {
    handleGameLinkMessage(client, message);
    return;
  }

  if (message.type !== "hello" && !client.helloReceived) {
    sendError(client.ws, "SESSION_NOT_READY", "PARDEX oturumu henüz hazır değil.");
    return;
  }

  switch (message.type) {
    case "hello": {
      const clientProtocol = Number(message.client_protocol || 0);
      if (clientProtocol < MIN_CLIENT_PROTOCOL) {
        sendError(client.ws, "CLIENT_OUTDATED", "PARDEX'in eski sürüm. PARDEX'i güncelleyip yeniden aç.");
        client.ws?.close(1008, "PARDEX client outdated");
        return;
      }
      client.clientProtocol = clientProtocol;
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
      const accountResult = social.ensureAccount(accountId, client.displayName);
      client.displayName = accountResult.account.display_name;
      if (accountResult.nameTaken) {
        sendError(client.ws, "NAME_TAKEN", "Bu kullanıcı adı alınmış. Mevcut adın korundu.");
      }
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
        room_lifecycle_enabled: true,
        secure_game_handoff_enabled: true,
        protocol_version: PROTOCOL_VERSION,
        min_client_protocol: MIN_CLIENT_PROTOCOL,
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
    case "set_avatar": {
      if (!requireSocialAccount(client)) return;
      const result = social.setAvatar(client.accountId, message.data);
      if (!result.ok) {
        sendError(client.ws, result.code, "Profil resmi kaydedilemedi. Daha küçük bir JPG/PNG dene.");
        return;
      }
      pushSocialState(client.accountId);
      pushRelatedSocialStates(client.accountId);
      break;
    }
    case "get_avatar": {
      if (!requireSocialAccount(client)) return;
      const targetId = String(message.account_id || "");
      const avatar = social.getAvatar(targetId);
      send(client.ws, {
        type: "avatar_data",
        account_id: targetId,
        avatar_id: avatar ? avatar.avatar_id : "",
        data: avatar ? avatar.data : "",
      });
      break;
    }
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
      if (!room || !roomIsLobby(room)) return;
      const member = room.members.find((item) => item.userId === client.userId);
      if (!member) return;
      member.ready = Boolean(message.ready);
      broadcastRoom(room);
      break;
    }
    case "play_game":
      playGame(client, message);
      break;
    case "block_user": {
      if (!requireSocialAccount(client)) break;
      const targetId = String(message.account_id || "").trim();
      applySocialAction(client, social.blockUser(client.accountId, targetId), targetId);
      break;
    }
    case "unblock_user": {
      if (!requireSocialAccount(client)) break;
      const targetId = String(message.account_id || "").trim();
      applySocialAction(client, social.unblockUser(client.accountId, targetId), targetId);
      break;
    }
    case "report_user": {
      if (!requireSocialAccount(client)) break;
      const result = social.reportUser(client.accountId, String(message.account_id || "").trim(), message.reason);
      if (!result.ok) sendError(client.ws, result.code, result.message);
      else sendNotice(client.ws, result.code, result.message);
      break;
    }
    case "submit_bug_report":
      saveBugReport(client, message);
      break;
    case "send_chat":
      sendChat(client, message);
      break;
    case "get_chat_history":
      sendChatHistory(client, message);
      break;
    case "mark_chat_read":
      markChatRead(client, message);
      break;
    case "get_game_session":
      issueGameSession(client, message);
      break;
    case "start_game":
      startRoomGame(client);
      break;
    case "game_connected":
      reportGameConnected(client, message);
      break;
    case "launch_failed":
      reportGameLaunchFailed(client, message);
      break;
    case "game_ended":
      reportGameEnded(client, message);
      break;
    case "return_to_lobby":
      returnRoomToLobby(client);
      break;
    case "call_start":
      startCall(client, message);
      break;
    case "call_accept":
      answerCall(client, message, true);
      break;
    case "call_decline":
      answerCall(client, message, false);
      break;
    case "call_end":
      hangUp(client);
      break;
    case "call_mute":
      relayCallMute(client, message.muted);
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
  if (req.url === "/admin/reports") {
    const token = String(process.env.PARDEX_ADMIN_TOKEN || "");
    const supplied = String(req.headers.authorization || "");
    const digest = (value) => crypto.createHash("sha256").update(value).digest();
    const allowed = token && req.method === "GET"
      && crypto.timingSafeEqual(digest(supplied), digest(`Bearer ${token}`));
    res.writeHead(allowed ? 200 : 403, {
      "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
    });
    res.end(JSON.stringify(allowed ? { reports: social.data.reports || [] } : { error: "forbidden" }));
    return;
  }
  if (req.url === "/admin/users") {
    const token = String(process.env.PARDEX_ADMIN_TOKEN || "");
    const supplied = String(req.headers.authorization || "");
    const digest = (value) => crypto.createHash("sha256").update(value).digest();
    const allowed = token && req.method === "GET"
      && crypto.timingSafeEqual(digest(supplied), digest(`Bearer ${token}`));
    res.writeHead(allowed ? 200 : 403, {
      "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
    });
    res.end(JSON.stringify(allowed
      ? userSummary(social.data.accounts, presenceForAccount)
      : { error: "forbidden" }));
    return;
  }
  if (req.url === "/health") {
    pruneGameLaunchTickets();
    const status = shuttingDown ? 503 : 200;
    const connectedClients = Array.from(clients.values()).filter((client) => client.ws).length;
    const lifecycleCounts = { lobby: 0, launching: 0, in_game: 0, ended: 0 };
    for (const room of rooms.values()) {
      const state = roomState(room);
      if (Object.prototype.hasOwnProperty.call(lifecycleCounts, state)) lifecycleCounts[state] += 1;
    }
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
      korsanGameServerAssigned: KORSAN_GAME_SERVER_URLS.length > 0,
      korsanGameServers: KORSAN_GAME_SERVER_URLS.length,
      voiceRelay: VOICE_RELAY_ENABLED,
      voiceCalls: true,
      presence: true,
      friendRoomJoin: true,
      accountRecovery: true,
      roomLifecycle: true,
      secureGameHandoff: true,
      gameLaunchTicketTtlMs: GAME_LAUNCH_TICKET_TTL_MS,
      pendingGameLaunchTickets: gameLaunchTickets.size,
      roomLifecycleCounts: lifecycleCounts,
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
    if (client.gameLinkOf) {
      const owner = clients.get(client.gameLinkOf);
      if (owner && owner.gameWs === ws) owner.gameWs = null;
      return;
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
  gameLaunchTickets.clear();
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
