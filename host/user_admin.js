"use strict";
const fs = require("fs");
const { userSummary } = require("../server/user_admin");

async function readUsers({ running, dataPath, token, port }) {
  if (running) {
    const response = await fetch(`http://127.0.0.1:${port}/admin/users`, {
      headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(2500),
    });
    if (!response.ok) throw new Error("Kullanıcı listesi alınamadı.");
    return response.json();
  }
  let data;
  try { data = JSON.parse(fs.readFileSync(dataPath, "utf8")); }
  catch (error) {
    if (error.code === "ENOENT") return userSummary({});
    throw new Error("Kayıtlı kullanıcı verisi okunamadı.");
  }
  if (!data.accounts || typeof data.accounts !== "object" || Array.isArray(data.accounts)) {
    throw new Error("Kayıtlı kullanıcı verisi geçersiz.");
  }
  return userSummary(data.accounts);
}

module.exports = { readUsers };
