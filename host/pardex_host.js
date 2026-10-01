#!/usr/bin/env node
"use strict";

// PARDEX ev sunucusu.
//
// Sunucuyu oyunu kuran kişinin bilgisayarında çalıştırır:
//   1. PARDEX Online sunucusu (server/production_server.js), 127.0.0.1:8765
//   2. Korsanların Hazinesi oyun sunucusu (dışa aktarılmış .exe, headless), 127.0.0.1:8766
//   3. Her ikisi için ücretsiz Cloudflare Quick Tunnel (hesap gerekmez)
//   4. Güncel wss:// adresini GitHub'daki sunucu-adresi dalına online.json olarak yazar.
// PARDEX istemcileri adresi oradan okur; arkadaşların hiçbir ayar yapmaz.
//
// Kullanım: PARDEX-Sunucu.bat (Windows) veya `node host/pardex_host.js`.
// `--yerel` yalnızca bu bilgisayarda test eder (tünel ve GitHub güncellemesi yok).

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const readline = require("readline");
const { spawn, spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const SERVER_DIR = path.join(ROOT, "server");
const BIN_DIR = path.join(__dirname, "bin");
const CONFIG_PATH = path.join(__dirname, "pardex_host.local.json");
const DATA_PATH = path.join(__dirname, "data", "social.json");
const REPO = "SerkanAydin06/Pardex";
const ADDRESS_BRANCH = "sunucu-adresi";
const ADDRESS_FILE = "online.json";
const ONLINE_PORT = 8765;
const GAME_PORT = 8766;
const LOCAL_ONLY = process.argv.includes("--yerel");
const IS_WINDOWS = process.platform === "win32";

const children = [];
let shuttingDown = false;
let config = {};

function log(message) {
  console.log(`[PARDEX] ${message}`);
}

function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (answer) => {
    rl.close();
    resolve(answer.trim().replace(/^"|"$/g, ""));
  }));
}

function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
  } catch {
    return {};
  }
}

function saveConfig() {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), "utf8");
}

function findKorsanExecutable() {
  const name = IS_WINDOWS ? "KorsanlarinHazinesi.exe" : "KorsanlarinHazinesi.x86_64";
  const candidates = [
    path.join(ROOT, "..", "Korsanlarin-Hazinesi", "build", name),
    path.join(ROOT, "..", "korsanlarin-hazinesi", "build", name),
    path.join(ROOT, "build", "games", "korsanlar", name),
    path.join(ROOT, "games", "korsanlar", name),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) || "";
}

async function setupConfig() {
  config = loadConfig();
  let changed = false;
  if (!config.game_token) {
    config.game_token = crypto.randomBytes(32).toString("hex");
    changed = true;
  }
  if (config.korsan_exe === undefined || (config.korsan_exe && !fs.existsSync(config.korsan_exe))) {
    const found = findKorsanExecutable();
    if (found) {
      config.korsan_exe = found;
    } else {
      console.log("");
      log("Korsanların Hazinesi oyun sunucusu için dışa aktarılmış oyun dosyası gerekli.");
      log("Örnek: C:\\Oyunlar\\Korsanlarin-Hazinesi\\build\\KorsanlarinHazinesi.exe");
      const answer = await ask("KorsanlarinHazinesi.exe yolu (atlamak için boş bırak): ");
      config.korsan_exe = answer && fs.existsSync(answer) ? answer : "";
      if (answer && !config.korsan_exe) log("Dosya bulunamadı; oyun sunucusu bu sefer açılmayacak.");
    }
    changed = true;
  }
  if (!LOCAL_ONLY && !config.github_token) {
    console.log("");
    log("İlk kurulum: arkadaşlarının sunucuyu otomatik bulması için GitHub anahtarı gerekiyor.");
    log("1) https://github.com/settings/personal-access-tokens/new adresini aç.");
    log("2) Repository access: Only select repositories -> SerkanAydin06/Pardex");
    log("3) Permissions -> Repository permissions -> Contents: Read and write");
    log("4) Generate token'a bas ve çıkan anahtarı buraya yapıştır.");
    config.github_token = await ask("GitHub anahtarı: ");
    changed = true;
  }
  if (changed) saveConfig();
}

function ensureServerDependencies() {
  if (fs.existsSync(path.join(SERVER_DIR, "node_modules", "ws"))) return;
  log("Sunucu bileşenleri kuruluyor (yalnızca ilk sefer)...");
  const result = spawnSync(IS_WINDOWS ? "npm.cmd" : "npm", ["install", "--omit=dev"], {
    cwd: SERVER_DIR,
    stdio: "inherit",
    shell: IS_WINDOWS,
  });
  if (result.status !== 0) throw new Error("npm install başarısız oldu.");
}

async function ensureCloudflared() {
  const name = IS_WINDOWS ? "cloudflared.exe" : "cloudflared";
  const local = path.join(BIN_DIR, name);
  if (fs.existsSync(local)) return local;
  if (!IS_WINDOWS && spawnSync("cloudflared", ["--version"]).status === 0) return "cloudflared";
  const asset = IS_WINDOWS ? "cloudflared-windows-amd64.exe" : "cloudflared-linux-amd64";
  log("Cloudflare tünel aracı indiriliyor (yalnızca ilk sefer)...");
  const response = await fetch(`https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}`);
  if (!response.ok) throw new Error(`cloudflared indirilemedi (HTTP ${response.status}).`);
  fs.mkdirSync(BIN_DIR, { recursive: true });
  fs.writeFileSync(local, Buffer.from(await response.arrayBuffer()));
  if (!IS_WINDOWS) fs.chmodSync(local, 0o755);
  return local;
}

function track(label, child, critical) {
  children.push(child);
  child.on("exit", (code) => {
    if (shuttingDown) return;
    log(`${label} kapandı (kod ${code}).`);
    if (critical) shutdown(1);
  });
  return child;
}

function openTunnel(cloudflared, port, label) {
  return new Promise((resolve, reject) => {
    const child = track(label, spawn(cloudflared, [
      "tunnel", "--no-autoupdate", "--url", `http://127.0.0.1:${port}`,
    ], { stdio: ["ignore", "pipe", "pipe"], windowsHide: true }), true);
    const timer = setTimeout(() => reject(new Error(`${label} 60 saniyede açılamadı.`)), 60_000);
    const onData = (chunk) => {
      const match = String(chunk).match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
      if (!match) return;
      clearTimeout(timer);
      child.stdout.off("data", onData);
      child.stderr.off("data", onData);
      resolve(match[0].replace("https://", "wss://"));
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
  });
}

function startOnlineServer(gameServerUrl) {
  fs.mkdirSync(path.dirname(DATA_PATH), { recursive: true });
  const env = {
    ...process.env,
    HOST: "127.0.0.1",
    PORT: String(ONLINE_PORT),
    PARDEX_SOCIAL_DATA_PATH: DATA_PATH,
    PARDEX_GAME_SERVER_TOKEN: config.game_token,
    KORSAN_GAME_SERVER_URL: gameServerUrl,
  };
  track("PARDEX Online sunucusu", spawn(process.execPath, ["production_server.js"], {
    cwd: SERVER_DIR,
    env,
    stdio: ["ignore", "inherit", "inherit"],
  }), true);
}

async function waitForHealth() {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${ONLINE_PORT}/health`);
      if (response.ok) return;
    } catch {
      // Not listening yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("PARDEX Online sunucusu başlamadı.");
}

function startGameServer() {
  if (!config.korsan_exe) return false;
  const env = {
    ...process.env,
    PARDEX_GAME_SERVER_TOKEN: config.game_token,
    PARDEX_SESSION: "*",
  };
  track("Korsanların Hazinesi oyun sunucusu", spawn(config.korsan_exe, [
    "--headless",
    "res://scenes/pardex_dedicated_server.tscn",
    "--",
    "--pardex-dedicated",
    `--pardex-port=${GAME_PORT}`,
    `--pardex-online-server=ws://127.0.0.1:${ONLINE_PORT}`,
  ], { cwd: path.dirname(config.korsan_exe), env, stdio: ["ignore", "inherit", "inherit"], windowsHide: true }), false);
  return true;
}

async function github(method, endpoint, body) {
  const response = await fetch(`https://api.github.com/repos/${REPO}${endpoint}`, {
    method,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${config.github_token}`,
      "User-Agent": "pardex-host",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json().catch(() => ({}));
  return { status: response.status, data };
}

async function publishAddress(onlineUrl) {
  const filePath = `/contents/${ADDRESS_FILE}`;
  let current = await github("GET", `${filePath}?ref=${ADDRESS_BRANCH}`);
  if (current.status === 404) {
    const branch = await github("GET", `/git/ref/heads/${ADDRESS_BRANCH}`);
    if (branch.status === 404) {
      const main = await github("GET", "/git/ref/heads/main");
      if (main.status !== 200) throw new Error(`GitHub erişimi reddedildi (HTTP ${main.status}). Anahtarı kontrol et.`);
      const created = await github("POST", "/git/refs", {
        ref: `refs/heads/${ADDRESS_BRANCH}`,
        sha: main.data.object.sha,
      });
      if (created.status !== 201) throw new Error(`Adres dalı oluşturulamadı (HTTP ${created.status}).`);
    }
    current = { status: 404, data: {} };
  } else if (current.status !== 200) {
    throw new Error(`GitHub erişimi reddedildi (HTTP ${current.status}). Anahtarı kontrol et.`);
  }
  const content = JSON.stringify({ online: onlineUrl, updated_at: new Date().toISOString() }, null, 2) + "\n";
  const result = await github("PUT", filePath, {
    message: onlineUrl ? "PARDEX sunucusu açık" : "PARDEX sunucusu kapalı",
    content: Buffer.from(content).toString("base64"),
    branch: ADDRESS_BRANCH,
    sha: current.data.sha,
  });
  if (result.status !== 200 && result.status !== 201) {
    throw new Error(`Sunucu adresi yayınlanamadı (HTTP ${result.status}).`);
  }
}

async function shutdown(code = 0) {
  if (shuttingDown) return;
  shuttingDown = true;
  log("Kapatılıyor...");
  if (!LOCAL_ONLY && config.github_token) {
    await Promise.race([
      publishAddress("").catch(() => {}),
      new Promise((resolve) => setTimeout(resolve, 5000)),
    ]);
  }
  for (const child of children) {
    try { child.kill(); } catch { /* already gone */ }
  }
  process.exit(code);
}

async function main() {
  console.log("==============================================");
  console.log("  PARDEX Sunucusu");
  console.log("  Kapatmak için bu pencerede Ctrl+C'ye bas.");
  console.log("==============================================");
  await setupConfig();
  ensureServerDependencies();

  let onlineUrl = `ws://127.0.0.1:${ONLINE_PORT}`;
  let gameUrl = config.korsan_exe ? `ws://127.0.0.1:${GAME_PORT}` : "";
  if (!LOCAL_ONLY) {
    const cloudflared = await ensureCloudflared();
    log("İnternet tünelleri açılıyor...");
    const tunnels = [openTunnel(cloudflared, ONLINE_PORT, "PARDEX tüneli")];
    if (config.korsan_exe) tunnels.push(openTunnel(cloudflared, GAME_PORT, "Oyun tüneli"));
    [onlineUrl, gameUrl = ""] = await Promise.all(tunnels);
  }

  startOnlineServer(gameUrl);
  await waitForHealth();
  const gameStarted = startGameServer();

  if (!LOCAL_ONLY) {
    log("Adres arkadaşlarına duyuruluyor...");
    await publishAddress(onlineUrl);
  }

  console.log("");
  log("SUNUCU AÇIK");
  log(`PARDEX adresi : ${onlineUrl}`);
  log(gameStarted ? `Oyun sunucusu: ${gameUrl}` : "Oyun sunucusu: kapalı (KorsanlarinHazinesi.exe ayarlanmadı)");
  log(LOCAL_ONLY
    ? "Yerel test modu: yalnızca bu bilgisayar bağlanabilir."
    : "Arkadaşların PARDEX'i açınca otomatik bağlanır. Bu pencere açık kaldıkça sunucu çalışır.");
}

process.on("SIGINT", () => shutdown(0));
process.on("SIGTERM", () => shutdown(0));
if (IS_WINDOWS) process.on("SIGHUP", () => shutdown(0));

main().catch((error) => {
  log(`HATA: ${error.message}`);
  shutdown(1);
});
