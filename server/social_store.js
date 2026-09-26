const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

function accountIdFromIdentityKey(value) {
  const identityKey = String(value || "").trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(identityKey)) return "";
  const digest = crypto
    .createHash("sha256")
    .update(`pardex-account-v1:${identityKey}`)
    .digest("hex");
  return `px_${digest.slice(0, 24)}`;
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
    this.data = { version: 1, accounts: {} };
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
        this.data.accounts[accountId] = {
          display_name: safeStoredName(raw.display_name),
          created_at: Number(raw.created_at || Date.now()),
          updated_at: Number(raw.updated_at || Date.now()),
          friends: safeArray(raw.friends),
          incoming_requests: safeArray(raw.incoming_requests),
          outgoing_requests: safeArray(raw.outgoing_requests),
        };
      }
      this.repairRelationships();
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
};
