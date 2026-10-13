"use strict";

// Deliberate whitelist: never return identities, recovery hashes or messages.
function userSummary(accounts, presenceFor = () => ({ presence: "offline" })) {
  const users = Object.entries(accounts).map(([accountId, account]) => {
    const status = presenceFor(accountId);
    return {
      account_id: accountId,
      display_name: String(account.display_name || "Pardus"),
      created_at: Number(account.created_at || 0),
      updated_at: Number(account.updated_at || 0),
      friend_count: Array.isArray(account.friends) ? account.friends.length : 0,
      online: status.presence !== "offline",
      presence: status.presence,
      in_game: Boolean(status.in_game),
    };
  }).sort((a, b) => Number(b.online) - Number(a.online)
    || a.display_name.localeCompare(b.display_name, "tr"));
  return { total: users.length, online: users.filter((user) => user.online).length, users };
}

module.exports = { userSummary };
