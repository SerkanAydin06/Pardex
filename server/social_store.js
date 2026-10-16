const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const IDENTITY_KEY_PATTERN = /^[a-f0-9]{64}$/;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const RECOVERY_CODE_PATTERN = /^PX1[A-F0-9]{32}$/;
// Profile pictures: small client-made JPEG/PNG (96 px) as base64, well under
// the 16 KB WebSocket payload limit.
const AVATAR_MAX_BASE64 = 12000;
const AVATAR_BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

function normalizeAvatar(value) {
  const text = String(value || "").trim();
  if (!text || text.length > AVATAR_MAX_BASE64 || !AVATAR_BASE64_PATTERN.test(text)) return "";
  const bytes = Buffer.from(text, "base64");
  const isJpeg = bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes.length > 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  return isJpeg || isPng ? text : "";
}

function avatarIdFor(avatar) {
  return avatar ? crypto.createHash("sha256").update(avatar).digest("hex").slice(0, 16) : "";
}

function normalizeIdentityKey(value) {
  const identityKey = String(value || "").trim().toLowerCase();
  return IDENTITY_KEY_PATTERN.test(identityKey) ? identityKey : "";
}

function accountIdFromIdentityKey(value) {
  const identityKey = normalizeIdentityKey(value);
  if (!identityKey) return "";
  const digest = crypto
    .createHash("sha256")
    .update(`pardex-account-v1:${identityKey}`)
    .digest("hex");
  return `px_${digest.slice(0, 24)}`;
}

function identityAliasFromKey(value) {
  const identityKey = normalizeIdentityKey(value);
  if (!identityKey) return "";
  return crypto
    .createHash("sha256")
    .update(`pardex-identity-alias-v1:${identityKey}`)
    .digest("hex");
}

function normalizeRecoveryCode(value) {
  const compact = String(value || "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
  return RECOVERY_CODE_PATTERN.test(compact) ? compact : "";
}

function recoveryCodeHash(value) {
  const recoveryCode = normalizeRecoveryCode(value);
  if (!recoveryCode) return "";
  return crypto
    .createHash("sha256")
    .update(`pardex-recovery-v1:${recoveryCode}`)
    .digest("hex");
}

function safeArray(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item || "").trim()).filter(Boolean))];
}

function safeStoredName(value) {
  const text = String(value || "Pardus").normalize("NFKC").trim().replace(/\s+/g, " ");
  return (text || "Pardus").slice(0, 24);
}

function nameKey(value) {
  return safeStoredName(value).toLocaleLowerCase("tr-TR");
}

const MAX_CONVERSATION_MESSAGES = 200;
const MAX_REPORTS = 500;
const BACKUP_DAYS = 14;
const MAX_CHAT_TEXT = 500;

function conversationKey(a, b) {
  return [String(a), String(b)].sort().join("|");
}

function cleanChatText(value) {
  return String(value || "")
    .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, MAX_CHAT_TEXT);
}

class SocialStore {
  constructor(filePath) {
    this.filePath = filePath;
    this.data = { version: 2, accounts: {}, identity_aliases: {}, conversations: {} };
    this.nameOwners = new Map();
    this.load();
  }

  load() {
    try {
      if (!fs.existsSync(this.filePath)) return;
      const parsed = JSON.parse(fs.readFileSync(this.filePath, "utf8"));
      if (!parsed || typeof parsed !== "object") return;
      const accounts = parsed.accounts && typeof parsed.accounts === "object"
        ? parsed.accounts
        : {};

      for (const [accountId, raw] of Object.entries(accounts)) {
        if (!accountId.startsWith("px_") || !raw || typeof raw !== "object") continue;
        const recoveryHash = String(raw.recovery_hash || "").trim().toLowerCase();
        this.data.accounts[accountId] = {
          display_name: safeStoredName(raw.display_name),
          created_at: Number(raw.created_at || Date.now()),
          updated_at: Number(raw.updated_at || Date.now()),
          friends: safeArray(raw.friends),
          incoming_requests: safeArray(raw.incoming_requests),
          outgoing_requests: safeArray(raw.outgoing_requests),
          blocked: safeArray(raw.blocked),
          recovery_hash: HASH_PATTERN.test(recoveryHash) ? recoveryHash : "",
          recovery_updated_at: Number(raw.recovery_updated_at || 0),
          avatar: normalizeAvatar(raw.avatar),
        };
      }

      const aliases = parsed.identity_aliases && typeof parsed.identity_aliases === "object"
        ? parsed.identity_aliases
        : {};
      for (const [fingerprint, accountId] of Object.entries(aliases)) {
        const normalizedFingerprint = String(fingerprint || "").trim().toLowerCase();
        const normalizedAccountId = String(accountId || "").trim();
        if (!HASH_PATTERN.test(normalizedFingerprint)) continue;
        if (!this.data.accounts[normalizedAccountId]) continue;
        this.data.identity_aliases[normalizedFingerprint] = normalizedAccountId;
      }

      this.data.reports = Array.isArray(parsed.reports) ? parsed.reports.slice(-MAX_REPORTS) : [];
      const conversations = parsed.conversations && typeof parsed.conversations === "object"
        ? parsed.conversations
        : {};
      for (const [key, raw] of Object.entries(conversations)) {
        const ids = String(key).split("|");
        if (ids.length !== 2 || !ids.every((id) => this.data.accounts[id]) || !raw) continue;
        const messages = Array.isArray(raw.messages) ? raw.messages : [];
        this.data.conversations[key] = {
          messages: messages
            .filter((item) => item && ids.includes(item.from) && typeof item.text === "string")
            .slice(-MAX_CONVERSATION_MESSAGES)
            .map((item) => ({
              id: String(item.id || crypto.randomUUID()),
              from: item.from,
              text: cleanChatText(item.text),
              at: Number(item.at || 0),
            })),
          read: raw.read && typeof raw.read === "object" ? {
            [ids[0]]: Number(raw.read[ids[0]] || 0),
            [ids[1]]: Number(raw.read[ids[1]] || 0),
          } : {},
        };
      }

      this.repairRelationships();
      this.repairIdentityAliases();
      this.data.version = 2;
      if (this.repairNames()) this.save();
    } catch (error) {
      console.error("PARDEX social data load failed:", error.message);
    }
  }

  availableName(name) {
    if (!this.nameOwners.has(nameKey(name))) return name;
    for (let number = 2; ; number += 1) {
      const suffix = `_${number}`;
      const candidate = name.slice(0, 24 - suffix.length) + suffix;
      if (!this.nameOwners.has(nameKey(candidate))) return candidate;
    }
  }

  repairNames() {
    const ordered = Object.entries(this.data.accounts).sort((a, b) =>
      a[1].created_at - b[1].created_at || a[0].localeCompare(b[0]));
    const duplicates = [];
    for (const [id, account] of ordered) {
      const key = nameKey(account.display_name);
      if (this.nameOwners.has(key)) duplicates.push([id, account]);
      else this.nameOwners.set(key, id);
    }
    for (const [id, account] of duplicates) {
      account.display_name = this.availableName(account.display_name);
      account.updated_at = Date.now();
      this.nameOwners.set(nameKey(account.display_name), id);
    }
    return duplicates.length > 0;
  }

  repairRelationships() {
    const ids = new Set(Object.keys(this.data.accounts));
    for (const [accountId, account] of Object.entries(this.data.accounts)) {
      account.friends = account.friends.filter((id) => id !== accountId && ids.has(id));
      account.incoming_requests = account.incoming_requests.filter(
        (id) => id !== accountId && ids.has(id) && !account.friends.includes(id)
      );
      account.outgoing_requests = account.outgoing_requests.filter(
        (id) => id !== accountId && ids.has(id) && !account.friends.includes(id)
      );
      account.blocked = (account.blocked || []).filter((id) => id !== accountId && ids.has(id));
    }
  }

  repairIdentityAliases() {
    for (const [fingerprint, accountId] of Object.entries(this.data.identity_aliases)) {
      if (!HASH_PATTERN.test(fingerprint) || !this.data.accounts[accountId]) {
        delete this.data.identity_aliases[fingerprint];
      }
    }
  }

  save() {
    try {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
      const tempPath = `${this.filePath}.tmp`;
      fs.writeFileSync(tempPath, JSON.stringify(this.data, null, 2), "utf8");
      fs.renameSync(tempPath, this.filePath);
      this.dailyBackup();
      return true;
    } catch (error) {
      console.error("PARDEX social data save failed:", error.message);
      return false;
    }
  }

  // One copy per day next to the data file (backups/social-YYYY-MM-DD.json),
  // the last BACKUP_DAYS kept, so a bad write or mistake can be undone.
  dailyBackup() {
    try {
      const day = new Date().toISOString().slice(0, 10);
      if (this.lastBackupDay === day) return;
      const dir = path.join(path.dirname(this.filePath), "backups");
      const target = path.join(dir, `social-${day}.json`);
      fs.mkdirSync(dir, { recursive: true });
      if (!fs.existsSync(target)) fs.copyFileSync(this.filePath, target);
      this.lastBackupDay = day;
      const old = fs.readdirSync(dir).filter((name) => /^social-\d{4}-\d{2}-\d{2}\.json$/.test(name)).sort();
      for (const name of old.slice(0, Math.max(0, old.length - BACKUP_DAYS))) fs.rmSync(path.join(dir, name));
    } catch (error) {
      console.error("PARDEX social backup failed:", error.message);
    }
  }

  ensureAccount(accountId, displayName) {
    let normalizedName = safeStoredName(displayName);
    const now = Date.now();
    let account = this.data.accounts[accountId];
    let changed = false;
    const owner = this.nameOwners.get(nameKey(normalizedName));
    const nameTaken = Boolean(owner && owner !== accountId);
    if (nameTaken && account) return { account, changed: false, nameTaken: true };
    if (nameTaken) normalizedName = this.availableName(normalizedName);

    if (!account) {
      account = {
        display_name: normalizedName,
        created_at: now,
        updated_at: now,
        friends: [],
        incoming_requests: [],
        outgoing_requests: [],
        blocked: [],
        recovery_hash: "",
        recovery_updated_at: 0,
        avatar: "",
      };
      this.data.accounts[accountId] = account;
      changed = true;
    } else if (account.display_name !== normalizedName) {
      this.nameOwners.delete(nameKey(account.display_name));
      account.display_name = normalizedName;
      account.updated_at = now;
      changed = true;
    }

    this.nameOwners.set(nameKey(account.display_name), accountId);
    if (changed) this.save();
    return { account, changed, nameTaken: false };
  }

  getAccount(accountId) {
    return this.data.accounts[accountId] || null;
  }

  // Empty data removes the picture. Returns { ok, avatar_id } or { ok:false, code }.
  setAvatar(accountId, data) {
    const account = this.getAccount(accountId);
    if (!account) return { ok: false, code: "ACCOUNT_NOT_FOUND" };
    const raw = String(data || "").trim();
    const avatar = normalizeAvatar(raw);
    if (raw && !avatar) return { ok: false, code: "AVATAR_INVALID" };
    account.avatar = avatar;
    account.updated_at = Date.now();
    this.save();
    return { ok: true, avatar_id: avatarIdFor(avatar) };
  }

  getAvatar(accountId) {
    const account = this.getAccount(accountId);
    if (!account || !account.avatar) return null;
    return { avatar_id: avatarIdFor(account.avatar), data: account.avatar };
  }

  resolveAccountId(identityKey) {
    const legacyAccountId = accountIdFromIdentityKey(identityKey);
    const fingerprint = identityAliasFromKey(identityKey);
    if (!legacyAccountId || !fingerprint) return "";

    const mappedAccountId = this.data.identity_aliases[fingerprint];
    if (mappedAccountId && this.data.accounts[mappedAccountId]) return mappedAccountId;
    if (mappedAccountId) delete this.data.identity_aliases[fingerprint];

    // Existing v1 accounts may claim their first alias once. After an account has a
    // registered identity alias, unknown device keys may not fall back to the legacy
    // deterministic account id. This makes recovery a true device transfer: deleting
    // the previous alias permanently revokes that previous device after restart too.
    const existingAccountHasAlias = Object.values(this.data.identity_aliases).includes(legacyAccountId);
    if (this.data.accounts[legacyAccountId] && existingAccountHasAlias) return "";

    this.data.identity_aliases[fingerprint] = legacyAccountId;
    this.save();
    return legacyAccountId;
  }

  registerIdentity(accountId, identityKey) {
    const fingerprint = identityAliasFromKey(identityKey);
    if (!fingerprint || !accountId || !this.data.accounts[accountId]) return false;
    if (this.data.identity_aliases[fingerprint] === accountId) return true;
    this.data.identity_aliases[fingerprint] = accountId;
    return this.save();
  }

  hasRecoveryCode(accountId) {
    const account = this.getAccount(accountId);
    return Boolean(account && HASH_PATTERN.test(String(account.recovery_hash || "")));
  }

  setRecoveryCode(accountId, recoveryCode) {
    const account = this.getAccount(accountId);
    if (!account) {
      return { ok: false, code: "ACCOUNT_NOT_FOUND", message: "PARDEX hesabı bulunamadı." };
    }

    const normalizedCode = normalizeRecoveryCode(recoveryCode);
    if (!normalizedCode) {
      return { ok: false, code: "INVALID_RECOVERY_CODE", message: "Kurtarma kodu biçimi geçersiz." };
    }

    const hashedCode = recoveryCodeHash(normalizedCode);
    const collision = Object.entries(this.data.accounts).find(
      ([otherId, other]) => otherId !== accountId && other.recovery_hash === hashedCode
    );
    if (collision) {
      return { ok: false, code: "RECOVERY_CODE_CONFLICT", message: "Yeni bir kurtarma kodu oluşturup tekrar dene." };
    }

    account.recovery_hash = hashedCode;
    account.recovery_updated_at = Date.now();
    account.updated_at = Date.now();
    if (!this.save()) {
      return { ok: false, code: "RECOVERY_SAVE_FAILED", message: "Kurtarma bilgisi kaydedilemedi." };
    }
    return { ok: true, code: "RECOVERY_CODE_SAVED", message: "Hesap kurtarma kodu etkinleştirildi." };
  }

  recoverIdentity(identityKey, recoveryCode) {
    const fingerprint = identityAliasFromKey(identityKey);
    const legacyAccountId = accountIdFromIdentityKey(identityKey);
    const hashedCode = recoveryCodeHash(recoveryCode);
    if (!fingerprint || !legacyAccountId) {
      return { ok: false, code: "INVALID_IDENTITY", message: "PARDEX cihaz kimliği geçersiz." };
    }
    if (!hashedCode) {
      return { ok: false, code: "INVALID_RECOVERY_CODE", message: "Kurtarma kodu geçersiz veya süresi dolmuş." };
    }

    let recoveredAccountId = "";
    for (const [accountId, account] of Object.entries(this.data.accounts)) {
      if (account.recovery_hash === hashedCode) {
        recoveredAccountId = accountId;
        break;
      }
    }
    if (!recoveredAccountId) {
      return { ok: false, code: "INVALID_RECOVERY_CODE", message: "Kurtarma kodu geçersiz veya daha önce kullanılmış." };
    }

    const previousAccountId = this.data.identity_aliases[fingerprint] || legacyAccountId;

    // Recovery is a transfer, not an additional login. Remove every previous device
    // alias for the recovered account before assigning the replacement device.
    for (const [knownFingerprint, knownAccountId] of Object.entries(this.data.identity_aliases)) {
      if (knownAccountId === recoveredAccountId) delete this.data.identity_aliases[knownFingerprint];
    }
    this.data.identity_aliases[fingerprint] = recoveredAccountId;

    const recovered = this.data.accounts[recoveredAccountId];
    recovered.recovery_hash = "";
    recovered.recovery_updated_at = Date.now();
    recovered.updated_at = Date.now();

    if (!this.save()) {
      return { ok: false, code: "RECOVERY_SAVE_FAILED", message: "Hesap kurtarma bilgisi kaydedilemedi." };
    }

    if (previousAccountId !== recoveredAccountId) this.cleanupOrphanAccount(previousAccountId);
    return {
      ok: true,
      code: "ACCOUNT_RECOVERED",
      message: "PARDEX hesabı bu cihaza taşındı.",
      accountId: recoveredAccountId,
      previousAccountId,
    };
  }

  cleanupOrphanAccount(accountId) {
    const account = this.getAccount(accountId);
    if (!account) return false;
    const hasIdentity = Object.values(this.data.identity_aliases).includes(accountId);
    const hasRelationships = (
      account.friends.length > 0
      || account.incoming_requests.length > 0
      || account.outgoing_requests.length > 0
    );
    if (hasIdentity || hasRelationships || account.recovery_hash) return false;
    delete this.data.accounts[accountId];
    this.nameOwners.delete(nameKey(account.display_name));
    return this.save();
  }

  publicProfile(accountId, online = false, relationship = "none") {
    const account = this.getAccount(accountId);
    if (!account) return null;
    return {
      account_id: accountId,
      display_name: account.display_name,
      avatar_id: avatarIdFor(account.avatar),
      tag: accountId.slice(-6).toUpperCase(),
      online: Boolean(online),
      relationship,
    };
  }

  relationshipBetween(fromId, targetId) {
    const from = this.getAccount(fromId);
    if (!from) return "none";
    if ((from.blocked || []).includes(targetId)) return "blocked";
    if (from.friends.includes(targetId)) return "friend";
    if (from.incoming_requests.includes(targetId)) return "incoming";
    if (from.outgoing_requests.includes(targetId)) return "outgoing";
    return "none";
  }

  relatedAccountIds(accountId) {
    const account = this.getAccount(accountId);
    if (!account) return [];
    return [...new Set([
      accountId,
      ...account.friends,
      ...account.incoming_requests,
      ...account.outgoing_requests,
    ])];
  }

  socialState(accountId, isOnline) {
    const account = this.getAccount(accountId);
    if (!account) return null;

    const profileFor = (targetId, relationship) => this.publicProfile(
      targetId,
      isOnline(targetId),
      relationship
    );

    return {
      self: this.publicProfile(accountId, isOnline(accountId), "self"),
      friends: account.friends
        .map((id) => profileFor(id, "friend"))
        .filter(Boolean)
        .sort((a, b) => Number(b.online) - Number(a.online) || a.display_name.localeCompare(b.display_name)),
      incoming_requests: account.incoming_requests
        .map((id) => profileFor(id, "incoming"))
        .filter(Boolean),
      outgoing_requests: account.outgoing_requests
        .map((id) => profileFor(id, "outgoing"))
        .filter(Boolean),
      blocked: (account.blocked || [])
        .map((id) => profileFor(id, "blocked"))
        .filter(Boolean),
    };
  }

  searchUsers(query, accountId, isOnline, limit = 12) {
    const normalized = String(query || "").trim().toLocaleLowerCase("tr-TR");
    if (normalized.length < 2) return [];

    return Object.entries(this.data.accounts)
      .filter(([targetId]) => targetId !== accountId)
      .map(([targetId, account]) => ({
        targetId,
        account,
        lowerName: account.display_name.toLocaleLowerCase("tr-TR"),
      }))
      .filter((item) => item.lowerName.includes(normalized) || item.targetId.toLowerCase().includes(normalized))
      .sort((a, b) => {
        const aPrefix = a.lowerName.startsWith(normalized) ? 1 : 0;
        const bPrefix = b.lowerName.startsWith(normalized) ? 1 : 0;
        if (aPrefix !== bPrefix) return bPrefix - aPrefix;
        const aOnline = isOnline(a.targetId) ? 1 : 0;
        const bOnline = isOnline(b.targetId) ? 1 : 0;
        if (aOnline !== bOnline) return bOnline - aOnline;
        return a.account.display_name.localeCompare(b.account.display_name);
      })
      .slice(0, limit)
      .map((item) => this.publicProfile(
        item.targetId,
        isOnline(item.targetId),
        this.relationshipBetween(accountId, item.targetId)
      ));
  }

  sendFriendRequest(fromId, targetId) {
    if (fromId === targetId) return { ok: false, code: "SELF_REQUEST", message: "Kendine arkadaşlık isteği gönderemezsin." };
    const from = this.getAccount(fromId);
    const target = this.getAccount(targetId);
    if (!from || !target) return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    if (from.friends.includes(targetId)) return { ok: false, code: "ALREADY_FRIENDS", message: "Bu kullanıcı zaten arkadaş listende." };
    if ((from.blocked || []).includes(targetId)) return { ok: false, code: "USER_BLOCKED", message: "Bu kullanıcıyı engelledin; önce engeli kaldır." };
    // Do not reveal the block to the blocked user.
    if ((target.blocked || []).includes(fromId)) return { ok: true, code: "REQUEST_SENT", message: "Arkadaşlık isteği gönderildi." };
    if (from.outgoing_requests.includes(targetId)) return { ok: false, code: "REQUEST_EXISTS", message: "Arkadaşlık isteği zaten gönderildi." };

    if (from.incoming_requests.includes(targetId)) {
      return this.acceptFriendRequest(fromId, targetId);
    }

    from.outgoing_requests.push(targetId);
    target.incoming_requests.push(fromId);
    from.updated_at = Date.now();
    target.updated_at = Date.now();
    this.save();
    return { ok: true, code: "REQUEST_SENT", message: "Arkadaşlık isteği gönderildi." };
  }

  acceptFriendRequest(accountId, fromId) {
    const account = this.getAccount(accountId);
    const from = this.getAccount(fromId);
    if (!account || !from) return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    if (!account.incoming_requests.includes(fromId)) {
      return { ok: false, code: "REQUEST_NOT_FOUND", message: "Bekleyen arkadaşlık isteği bulunamadı." };
    }

    account.incoming_requests = account.incoming_requests.filter((id) => id !== fromId);
    from.outgoing_requests = from.outgoing_requests.filter((id) => id !== accountId);
    if (!account.friends.includes(fromId)) account.friends.push(fromId);
    if (!from.friends.includes(accountId)) from.friends.push(accountId);
    account.updated_at = Date.now();
    from.updated_at = Date.now();
    this.save();
    return { ok: true, code: "FRIEND_ADDED", message: "Arkadaşlık isteği kabul edildi." };
  }

  declineFriendRequest(accountId, fromId) {
    const account = this.getAccount(accountId);
    const from = this.getAccount(fromId);
    if (!account || !from) return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    if (!account.incoming_requests.includes(fromId)) {
      return { ok: false, code: "REQUEST_NOT_FOUND", message: "Bekleyen arkadaşlık isteği bulunamadı." };
    }

    account.incoming_requests = account.incoming_requests.filter((id) => id !== fromId);
    from.outgoing_requests = from.outgoing_requests.filter((id) => id !== accountId);
    account.updated_at = Date.now();
    from.updated_at = Date.now();
    this.save();
    return { ok: true, code: "REQUEST_DECLINED", message: "Arkadaşlık isteği reddedildi." };
  }

  cancelFriendRequest(accountId, targetId) {
    const account = this.getAccount(accountId);
    const target = this.getAccount(targetId);
    if (!account || !target) return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    if (!account.outgoing_requests.includes(targetId)) {
      return { ok: false, code: "REQUEST_NOT_FOUND", message: "Gönderilmiş arkadaşlık isteği bulunamadı." };
    }

    account.outgoing_requests = account.outgoing_requests.filter((id) => id !== targetId);
    target.incoming_requests = target.incoming_requests.filter((id) => id !== accountId);
    account.updated_at = Date.now();
    target.updated_at = Date.now();
    this.save();
    return { ok: true, code: "REQUEST_CANCELLED", message: "Arkadaşlık isteği iptal edildi." };
  }

  // ------------------------------------------------------------ chat

  conversation(accountId, otherId, create = false) {
    const key = conversationKey(accountId, otherId);
    if (!this.data.conversations[key] && create) {
      this.data.conversations[key] = { messages: [], read: {} };
    }
    return this.data.conversations[key] || null;
  }

  sendChatMessage(fromId, toId, text) {
    if (!this.getAccount(fromId) || !this.getAccount(toId)) {
      return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    }
    if (this.relationshipBetween(fromId, toId) !== "friend") {
      return { ok: false, code: "NOT_FRIENDS", message: "Yalnız arkadaşlarına mesaj gönderebilirsin." };
    }
    const clean = cleanChatText(text);
    if (!clean) return { ok: false, code: "EMPTY_MESSAGE", message: "Boş mesaj gönderilemez." };
    const conversation = this.conversation(fromId, toId, true);
    const message = { id: crypto.randomUUID(), from: fromId, text: clean, at: Date.now() };
    conversation.messages.push(message);
    if (conversation.messages.length > MAX_CONVERSATION_MESSAGES) {
      conversation.messages.splice(0, conversation.messages.length - MAX_CONVERSATION_MESSAGES);
    }
    conversation.read[fromId] = message.at;
    this.save();
    return { ok: true, message };
  }

  chatHistory(accountId, otherId) {
    return (this.conversation(accountId, otherId)?.messages || []).map((item) => ({ ...item }));
  }

  markChatRead(accountId, otherId) {
    const conversation = this.conversation(accountId, otherId);
    if (!conversation || conversation.messages.length === 0) return false;
    const last = conversation.messages[conversation.messages.length - 1].at;
    if (Number(conversation.read[accountId] || 0) >= last) return false;
    conversation.read[accountId] = last;
    this.save();
    return true;
  }

  // Last message and unread count with one friend, for lists and badges.
  chatSummary(accountId, otherId) {
    const conversation = this.conversation(accountId, otherId);
    if (!conversation || conversation.messages.length === 0) {
      return { chat_unread: 0, chat_last_text: "", chat_last_at: 0, chat_last_mine: false };
    }
    const readAt = Number(conversation.read[accountId] || 0);
    const last = conversation.messages[conversation.messages.length - 1];
    return {
      chat_unread: conversation.messages.filter((item) => item.from !== accountId && item.at > readAt).length,
      chat_last_text: last.text.slice(0, 80),
      chat_last_at: last.at,
      chat_last_mine: last.from === accountId,
    };
  }

  // Blocking ends friendship and pending requests both ways; the blocked
  // user can no longer message, request or invite (checks use relationship).
  blockUser(accountId, targetId) {
    const account = this.getAccount(accountId);
    const target = this.getAccount(targetId);
    if (!account || !target || accountId === targetId) return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    const drop = (list, id) => list.filter((item) => item !== id);
    account.friends = drop(account.friends, targetId);
    target.friends = drop(target.friends, accountId);
    account.incoming_requests = drop(account.incoming_requests, targetId);
    account.outgoing_requests = drop(account.outgoing_requests, targetId);
    target.incoming_requests = drop(target.incoming_requests, accountId);
    target.outgoing_requests = drop(target.outgoing_requests, accountId);
    account.blocked = [...new Set([...(account.blocked || []), targetId])];
    account.updated_at = Date.now();
    target.updated_at = Date.now();
    this.save();
    return { ok: true, code: "USER_BLOCKED", message: `${target.display_name} engellendi.` };
  }

  unblockUser(accountId, targetId) {
    const account = this.getAccount(accountId);
    if (!account || !(account.blocked || []).includes(targetId)) return { ok: false, code: "NOT_BLOCKED", message: "Bu kullanıcı engelli değil." };
    account.blocked = account.blocked.filter((id) => id !== targetId);
    account.updated_at = Date.now();
    this.save();
    return { ok: true, code: "USER_UNBLOCKED", message: "Engel kaldırıldı." };
  }

  isBlockedBetween(a, b) {
    return Boolean((this.getAccount(a)?.blocked || []).includes(b) || (this.getAccount(b)?.blocked || []).includes(a));
  }

  // Reports keep the last messages of the conversation as evidence for the
  // host (GET /admin/reports with the admin token).
  reportUser(accountId, targetId, reason) {
    const target = this.getAccount(targetId);
    if (!this.getAccount(accountId) || !target || accountId === targetId) return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    const recent = this.chatHistory(accountId, targetId).slice(-20);
    this.data.reports = [...(this.data.reports || []), {
      id: crypto.randomUUID(),
      from: accountId,
      target: targetId,
      target_name: target.display_name,
      reason: cleanChatText(reason).slice(0, 300) || "Belirtilmedi",
      at: Date.now(),
      messages: recent,
    }].slice(-MAX_REPORTS);
    this.save();
    return { ok: true, code: "USER_REPORTED", message: "Şikâyetin sunucu yöneticisine iletildi." };
  }

  removeFriend(accountId, targetId) {
    const account = this.getAccount(accountId);
    const target = this.getAccount(targetId);
    if (!account || !target) return { ok: false, code: "USER_NOT_FOUND", message: "Kullanıcı bulunamadı." };
    if (!account.friends.includes(targetId)) {
      return { ok: false, code: "NOT_FRIENDS", message: "Bu kullanıcı arkadaş listende değil." };
    }

    account.friends = account.friends.filter((id) => id !== targetId);
    target.friends = target.friends.filter((id) => id !== accountId);
    account.updated_at = Date.now();
    target.updated_at = Date.now();
    this.save();
    return { ok: true, code: "FRIEND_REMOVED", message: "Arkadaş listenden kaldırıldı." };
  }
}

module.exports = {
  SocialStore,
  accountIdFromIdentityKey,
  identityAliasFromKey,
  normalizeRecoveryCode,
};
