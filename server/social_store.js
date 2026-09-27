const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const IDENTITY_KEY_PATTERN = /^[a-f0-9]{64}$/;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const RECOVERY_CODE_PATTERN = /^PX1[A-F0-9]{32}$/;

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
  const text = String(value || "Pardus").trim().replace(/\s+/g, " ");
  return (text || "Pardus").slice(0, 24);
}

class SocialStore {
  constructor(filePath) {
    this.filePath = filePath;
    this.data = { version: 2, accounts: {}, identity_aliases: {} };
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
          recovery_hash: HASH_PATTERN.test(recoveryHash) ? recoveryHash : "",
          recovery_updated_at: Number(raw.recovery_updated_at || 0),
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

      this.repairRelationships();
      this.repairIdentityAliases();
      this.data.version = 2;
    } catch (error) {
      console.error("PARDEX social data load failed:", error.message);
    }
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
      return true;
    } catch (error) {
      console.error("PARDEX social data save failed:", error.message);
      return false;
    }
  }

  ensureAccount(accountId, displayName) {
    const normalizedName = safeStoredName(displayName);
    const now = Date.now();
    let account = this.data.accounts[accountId];
    let changed = false;

    if (!account) {
      account = {
        display_name: normalizedName,
        created_at: now,
        updated_at: now,
        friends: [],
        incoming_requests: [],
        outgoing_requests: [],
        recovery_hash: "",
        recovery_updated_at: 0,
      };
      this.data.accounts[accountId] = account;
      changed = true;
    } else if (account.display_name !== normalizedName) {
      account.display_name = normalizedName;
      account.updated_at = now;
      changed = true;
    }

    if (changed) this.save();
    return { account, changed };
  }

  getAccount(accountId) {
    return this.data.accounts[accountId] || null;
  }

  resolveAccountId(identityKey) {
    const legacyAccountId = accountIdFromIdentityKey(identityKey);
    const fingerprint = identityAliasFromKey(identityKey);
    if (!legacyAccountId || !fingerprint) return "";

    const mappedAccountId = this.data.identity_aliases[fingerprint];
    if (mappedAccountId && this.data.accounts[mappedAccountId]) return mappedAccountId;

    if (mappedAccountId) delete this.data.identity_aliases[fingerprint];
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
      message: "PARDEX hesabı bu cihaza bağlandı.",
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
    return this.save();
  }

  publicProfile(accountId, online = false, relationship = "none") {
    const account = this.getAccount(accountId);
    if (!account) return null;
    return {
      account_id: accountId,
      display_name: account.display_name,
      tag: accountId.slice(-6).toUpperCase(),
      online: Boolean(online),
      relationship,
    };
  }

  relationshipBetween(fromId, targetId) {
    const from = this.getAccount(fromId);
    if (!from) return "none";
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
