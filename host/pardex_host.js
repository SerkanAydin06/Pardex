#!/usr/bin/env node
"use strict";

// PARDEX Sunucu Paneli.
//
// Tarayıcıda açılan bir panelden, oyunu kuran kişinin bilgisayarında:
//   1. PARDEX Online sunucusunu (server/production_server.js, 127.0.0.1:8765)
//   2. Korsanların Hazinesi oyun sunucusunu (exe ya da Godot proje klasörü, 127.0.0.1:8766)
//   3. Her ikisi için ücretsiz Cloudflare Quick Tunnel'ı açar
//   4. Güncel wss:// adresini GitHub'daki sunucu-adresi dalına online.json olarak yazar.
// PARDEX istemcileri adresi oradan okur; arkadaşların hiçbir ayar yapmaz.
//
// Kullanım: PARDEX-Sunucu.bat (Windows) veya `node host/pardex_host.js`.

const fs = require("fs");
const http = require("http");
const path = require("path");
const crypto = require("crypto");
const { spawn, spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const SERVER_DIR = path.join(ROOT, "server");
const BIN_DIR = path.join(__dirname, "bin");
const PANEL_PATH = path.join(__dirname, "panel.html");
const CONFIG_PATH = path.join(__dirname, "pardex_host.local.json");
const DATA_PATH = path.join(__dirname, "data", "social.json");
const REPO = "SerkanAydin06/Pardex";
const ADDRESS_BRANCH = "sunucu-adresi";
const ADDRESS_FILE = "online.json";
const ONLINE_PORT = 8765;
const GAME_PORT = 8766;
const PANEL_PORT = Number(process.env.PARDEX_PANEL_PORT || 8790);
const IS_WINDOWS = process.platform === "win32";

let config = loadConfig();
let children = [];
const logs = [];
const state = {
  phase: "stopped", // stopped | starting | running | stopping | error
  message: "Başlatmak için düğmeye bas.",
  onlineUrl: "",
  gameUrl: "",
  localOnly: false,
};

// ------------------------------------------------------------------ helpers

function log(message, source = "PARDEX") {
  const line = `[${new Date().toLocaleTimeString("tr-TR")}] ${source}: ${message}`;
  console.log(line);
  logs.push(line);
  if (logs.length > 300) logs.splice(0, logs.length - 300);
}

function setPhase(phase, message) {
  state.phase = phase;
  state.message = message;
  log(message);
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

function cleanPath(value) {
  // Accept quoted paths and a dragged project.godot file as its folder.
  const clean = String(value || "").trim().replace(/^"|"$/g, "");
  return path.basename(clean).toLowerCase() === "project.godot" ? path.dirname(clean) : clean;
}

function isProjectFolder(target) {
  return Boolean(target) && fs.existsSync(path.join(target, "project.godot"));
}

function isFile(target) {
  return Boolean(target) && fs.existsSync(target) && fs.statSync(target).isFile();
}

function findKorsanGame() {
  const name = IS_WINDOWS ? "KorsanlarinHazinesi.exe" : "KorsanlarinHazinesi.x86_64";
  const folders = [
    path.join(ROOT, "..", "Korsanlarin-Hazinesi"),
    path.join(ROOT, "..", "korsanlarin-hazinesi"),
  ];
  const candidates = [
    ...folders.map((folder) => path.join(folder, "build", name)),
    path.join(ROOT, "build", "games", "korsanlar", name),
    ...folders,
  ];
  return candidates.find((candidate) => isProjectFolder(candidate) || isFile(candidate)) || "";
}

function gameStatus() {
  const target = config.korsan_exe || "";
  if (!target) return { ok: false, needsGodot: false, text: "Oyun yolu seçilmedi; yalnızca PARDEX açılır." };
  if (isProjectFolder(target)) {
    if (isFile(config.godot_exe)) return { ok: true, needsGodot: true, text: "Proje klasöründen Godot ile açılacak." };
    return { ok: false, needsGodot: true, text: "Proje klasörü için Godot .exe dosyasını seç." };
  }
  if (isFile(target)) return { ok: true, needsGodot: false, text: "Dışa aktarılmış oyun dosyası kullanılacak." };
  return { ok: false, needsGodot: false, text: "Seçilen oyun yolu bulunamadı." };
}

function ensureDefaults() {
  let changed = false;
  if (!config.game_token) {
    config.game_token = crypto.randomBytes(32).toString("hex");
    changed = true;
  }
  if (config.korsan_exe === undefined) {
    config.korsan_exe = findKorsanGame();
    changed = true;
  }
  if (changed) saveConfig();
}

// ------------------------------------------------------------------ processes

function ensureServerDependencies() {
  if (fs.existsSync(path.join(SERVER_DIR, "node_modules", "ws"))) return;
  log("Sunucu bileşenleri kuruluyor (yalnızca ilk sefer)...");
  const result = spawnSync(IS_WINDOWS ? "npm.cmd" : "npm", ["install", "--omit=dev"], {
    cwd: SERVER_DIR,
    stdio: "inherit",
    shell: IS_WINDOWS,
  });
  if (result.status !== 0) throw new Error("Sunucu bileşenleri kurulamadı (npm install).");
}

async function ensureCloudflared() {
  const name = IS_WINDOWS ? "cloudflared.exe" : "cloudflared";
  const local = path.join(BIN_DIR, name);
  if (fs.existsSync(local)) return local;
  if (!IS_WINDOWS && spawnSync("cloudflared", ["--version"]).status === 0) return "cloudflared";
  const asset = IS_WINDOWS ? "cloudflared-windows-amd64.exe" : "cloudflared-linux-amd64";
  log("Cloudflare tünel aracı indiriliyor (yalnızca ilk sefer)...");
  const response = await fetch(`https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}`);
  if (!response.ok) throw new Error(`Tünel aracı indirilemedi (HTTP ${response.status}).`);
  fs.mkdirSync(BIN_DIR, { recursive: true });
  fs.writeFileSync(local, Buffer.from(await response.arrayBuffer()));
  if (!IS_WINDOWS) fs.chmodSync(local, 0o755);
  return local;
}

function track(label, child, critical) {
  children.push(child);
  const forward = (chunk) => {
    for (const line of String(chunk).split(/\r?\n/)) {
      if (line.trim()) log(line.trim(), label);
    }
  };
  child.stdout?.on("data", forward);
  child.stderr?.on("data", forward);
  child.on("error", (error) => log(`başlatılamadı: ${error.message}`, label));
  child.on("exit", (code) => {
    children = children.filter((item) => item !== child);
    if (state.phase !== "running" && state.phase !== "starting") return;
    log(`kapandı (kod ${code}).`, label);
    if (critical) stopServer(`${label} beklenmedik şekilde kapandı.`);
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
  track("PARDEX Online", spawn(process.execPath, ["production_server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(ONLINE_PORT),
      PARDEX_SOCIAL_DATA_PATH: DATA_PATH,
      PARDEX_GAME_SERVER_TOKEN: config.game_token,
      KORSAN_GAME_SERVER_URL: gameServerUrl,
    },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
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
  const fromProject = isProjectFolder(config.korsan_exe);
  const program = fromProject ? config.godot_exe : config.korsan_exe;
  track("Oyun sunucusu", spawn(program, [
    "--headless",
    ...(fromProject ? ["--path", config.korsan_exe] : []),
    "res://scenes/pardex_dedicated_server.tscn",
    "--",
    "--pardex-dedicated",
    `--pardex-port=${GAME_PORT}`,
    `--pardex-online-server=ws://127.0.0.1:${ONLINE_PORT}`,
  ], {
    cwd: fromProject ? config.korsan_exe : path.dirname(config.korsan_exe),
    env: { ...process.env, PARDEX_GAME_SERVER_TOKEN: config.game_token, PARDEX_SESSION: "*" },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  }), false);
}

// ------------------------------------------------------------------ address board

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
      if (main.status !== 200) throw new Error(`GitHub anahtarı reddedildi (HTTP ${main.status}). Anahtarı kontrol et.`);
      const created = await github("POST", "/git/refs", { ref: `refs/heads/${ADDRESS_BRANCH}`, sha: main.data.object.sha });
      if (created.status !== 201) throw new Error(`Adres dalı oluşturulamadı (HTTP ${created.status}). Anahtarın "Contents: Read and write" izni olmalı.`);
    }
    current = { status: 404, data: {} };
  } else if (current.status !== 200) {
    throw new Error(`GitHub anahtarı reddedildi (HTTP ${current.status}). Anahtarı kontrol et.`);
  }
  const content = JSON.stringify({ online: onlineUrl, updated_at: new Date().toISOString() }, null, 2) + "\n";
  const result = await github("PUT", filePath, {
    message: onlineUrl ? "PARDEX sunucusu açık" : "PARDEX sunucusu kapalı",
    content: Buffer.from(content).toString("base64"),
    branch: ADDRESS_BRANCH,
    sha: current.data.sha,
  });
  if (result.status !== 200 && result.status !== 201) {
    throw new Error(`Sunucu adresi yayınlanamadı (HTTP ${result.status}). Anahtarın "Contents: Read and write" izni olmalı.`);
  }
}

// ------------------------------------------------------------------ start / stop

function killChildren() {
  for (const child of children) {
    try { child.kill(); } catch { /* already gone */ }
  }
  children = [];
}

async function startServer(localOnly) {
  if (state.phase === "starting" || state.phase === "running") return;
  state.localOnly = Boolean(localOnly);
  state.onlineUrl = "";
  state.gameUrl = "";
  try {
    setPhase("starting", "Sunucu başlatılıyor...");
    if (!state.localOnly && !config.github_token) {
      throw new Error("Önce GitHub anahtarını kaydet (Ayarlar bölümü).");
    }
    ensureServerDependencies();
    const game = gameStatus();
    let onlineUrl = `ws://127.0.0.1:${ONLINE_PORT}`;
    let gameUrl = game.ok ? `ws://127.0.0.1:${GAME_PORT}` : "";
    if (!state.localOnly) {
      const cloudflared = await ensureCloudflared();
      setPhase("starting", "İnternet tünelleri açılıyor...");
      const tunnels = [openTunnel(cloudflared, ONLINE_PORT, "PARDEX tüneli")];
      if (game.ok) tunnels.push(openTunnel(cloudflared, GAME_PORT, "Oyun tüneli"));
      [onlineUrl, gameUrl = ""] = await Promise.all(tunnels);
    }
    startOnlineServer(gameUrl);
    await waitForHealth();
    if (game.ok) startGameServer();
    if (!state.localOnly) {
      setPhase("starting", "Adres arkadaşlarına duyuruluyor...");
      await publishAddress(onlineUrl);
    }
    state.onlineUrl = onlineUrl;
    state.gameUrl = gameUrl;
    setPhase("running", state.localOnly
      ? "Sunucu açık (yerel test: yalnızca bu bilgisayar bağlanabilir)."
      : "Sunucu açık. Arkadaşların PARDEX'i açınca otomatik bağlanır.");
  } catch (error) {
    killChildren();
    setPhase("error", error.message);
  }
}

async function stopServer(reason = "Sunucu kapatıldı. Tekrar başlatmak için düğmeye bas.") {
  if (state.phase === "stopped" || state.phase === "stopping") return;
  const wasPublic = !state.localOnly && Boolean(state.onlineUrl);
  state.phase = "stopping";
  state.message = "Sunucu kapatılıyor...";
  killChildren();
  if (wasPublic) {
    await Promise.race([
      publishAddress("").catch((error) => log(`Kapalı durumu yayınlanamadı: ${error.message}`)),
      new Promise((resolve) => setTimeout(resolve, 5000)),
    ]);
  }
  state.onlineUrl = "";
  state.gameUrl = "";
  setPhase("stopped", reason);
}

// ------------------------------------------------------------------ panel

// Native Windows pickers so nobody has to type a path.
function browse(kind) {
  if (!IS_WINDOWS) return "";
  const script = kind === "folder"
    ? "Add-Type -AssemblyName System.Windows.Forms;" +
      "$d=New-Object System.Windows.Forms.FolderBrowserDialog;" +
      "$d.Description='Korsanlarin Hazinesi proje klasorunu sec (icinde project.godot olan)';" +
      "if($d.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost=$true})) -eq 'OK'){[Console]::Out.Write($d.SelectedPath)}"
    : "Add-Type -AssemblyName System.Windows.Forms;" +
      "$d=New-Object System.Windows.Forms.OpenFileDialog;" +
      `$d.Filter='${kind === "godot" ? "Godot|Godot*.exe|Tum exe dosyalari|*.exe" : "Oyun|*.exe"}';` +
      "if($d.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost=$true})) -eq 'OK'){[Console]::Out.Write($d.FileName)}";
  const result = spawnSync("powershell", ["-NoProfile", "-STA", "-Command", script], { encoding: "utf8" });
  return String(result.stdout || "").trim();
}

function publicState() {
  const game = gameStatus();
  return {
    ...state,
    logs: logs.slice(-120),
    config: {
      korsan_path: config.korsan_exe || "",
      godot_exe: config.godot_exe || "",
      has_token: Boolean(config.github_token),
    },
    game,
    canBrowse: IS_WINDOWS,
  };
}

function readBody(request) {
  return new Promise((resolve) => {
    let raw = "";
    request.on("data", (chunk) => { raw += chunk; if (raw.length > 65536) request.destroy(); });
    request.on("end", () => {
      try { resolve(JSON.parse(raw || "{}")); } catch { resolve({}); }
    });
  });
}

function sendJson(response, data, status = 200) {
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  response.end(JSON.stringify(data));
}

async function handle(request, response) {
  const url = new URL(request.url, "http://127.0.0.1");
  // Only this computer's browser may drive the panel.
  const origin = request.headers.origin;
  if (request.method === "POST" && origin && origin !== `http://127.0.0.1:${PANEL_PORT}` && origin !== `http://localhost:${PANEL_PORT}`) {
    return sendJson(response, { error: "forbidden" }, 403);
  }
  if (request.method === "GET" && url.pathname === "/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
    return response.end(fs.readFileSync(PANEL_PATH));
  }
  if (request.method === "GET" && url.pathname === "/api/state") return sendJson(response, publicState());
  if (request.method !== "POST") return sendJson(response, { error: "not found" }, 404);

  const body = await readBody(request);
  switch (url.pathname) {
    case "/api/config": {
      if (typeof body.korsan_path === "string") config.korsan_exe = cleanPath(body.korsan_path);
      if (typeof body.godot_exe === "string") config.godot_exe = cleanPath(body.godot_exe);
      if (typeof body.github_token === "string" && body.github_token.trim()) config.github_token = body.github_token.trim();
      saveConfig();
      log("Ayarlar kaydedildi.");
      return sendJson(response, publicState());
    }
    case "/api/browse": {
      const picked = browse(String(body.kind || ""));
      return sendJson(response, { path: picked ? cleanPath(picked) : "" });
    }
    case "/api/start":
      startServer(Boolean(body.local));
      return sendJson(response, publicState());
    case "/api/stop":
      await stopServer();
      return sendJson(response, publicState());
    case "/api/quit":
      sendJson(response, { ok: true });
      await stopServer();
      setTimeout(() => process.exit(0), 200);
      return undefined;
    default:
      return sendJson(response, { error: "not found" }, 404);
  }
}

function openBrowser(url) {
  if (process.env.PARDEX_NO_BROWSER) return;
  if (IS_WINDOWS) spawn("cmd", ["/c", "start", "", url], { detached: true, stdio: "ignore", windowsHide: true }).unref();
  else if (process.platform === "darwin") spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
}

function main() {
  ensureDefaults();
  const panelUrl = `http://127.0.0.1:${PANEL_PORT}/`;
  const server = http.createServer((request, response) => {
    handle(request, response).catch((error) => sendJson(response, { error: error.message }, 500));
  });
  server.on("error", (error) => {
    if (error.code === "EADDRINUSE") {
      console.log("PARDEX Sunucu Paneli zaten açık; tarayıcıda gösteriliyor.");
      openBrowser(panelUrl);
      setTimeout(() => process.exit(0), 500);
      return;
    }
    throw error;
  });
  server.listen(PANEL_PORT, "127.0.0.1", () => {
    console.log("==============================================");
    console.log("  PARDEX Sunucu Paneli");
    console.log(`  ${panelUrl}`);
    console.log("  Panel tarayıcıda açıldı. Sunucu açıkken bu pencereyi kapatma.");
    console.log("==============================================");
    log("Panel hazır.");
    openBrowser(panelUrl);
  });
}

const shutdown = () => stopServer().finally(() => process.exit(0));
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.on("SIGHUP", shutdown);

main();
