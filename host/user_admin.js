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

// Reports filed by players (block/report menu), newest first.
async function readReports({ running, dataPath, token, port }) {
  if (running) {
    const response = await fetch(`http://127.0.0.1:${port}/admin/reports`, {
      headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(2500),
    });
    if (!response.ok) throw new Error("Şikâyetler alınamadı.");
    const body = await response.json();
    return { reports: (body.reports || []).slice().reverse() };
  }
  try {
    const data = JSON.parse(fs.readFileSync(dataPath, "utf8"));
    return { reports: (Array.isArray(data.reports) ? data.reports : []).slice().reverse() };
  } catch (error) {
    if (error.code === "ENOENT") return { reports: [] };
    throw new Error("Kayıtlı şikâyetler okunamadı.");
  }
}

module.exports = { readUsers, readReports };
