#!/usr/bin/env node
"use strict";

// PARDEX Sunucu Paneli.
//
// Tarayıcıda açılan bir panelden, oyunu kuran kişinin bilgisayarında:
//   1. PARDEX Online sunucusunu (server/production_server.js, 127.0.0.1:8765)
//   2. Korsanların Hazinesi oyun sunucusunu (exe ya da Godot proje klasörü, 127.0.0.1:8766)
//   3. Her ikisi için ücretsiz Cloudflare Quick Tunnel'ı açar
//   4. Güncel wss:// adresini kendi dağıtım sunucuna online.json olarak yazar.
// PARDEX istemcileri adresi oradan okur; arkadaşların hiçbir ayar yapmaz.
//
// Kullanım: PARDEX-Sunucu.bat (Windows) veya `node host/pardex_host.js`.

const fs = require("fs");
const net = require("net");
const http = require("http");
const path = require("path");
const crypto = require("crypto");
const { spawn, spawnSync } = require("child_process");
const { readUsers, readReports, readBugReports } = require("./user_admin");

const ROOT = path.resolve(__dirname, "..");
const SERVER_DIR = path.join(ROOT, "server");
const BIN_DIR = path.join(__dirname, "bin");
const PANEL_PATH = path.join(__dirname, "panel.html");
const CONFIG_PATH = path.join(__dirname, "pardex_host.local.json");
const DATA_PATH = path.join(__dirname, "data", "social.json");
const ONLINE_PORT = 8765;
// Table N's game server listens on GAME_PORT + N.
const GAME_PORT = 8766;
const MAX_TABLES = 4;
const PANEL_PORT = Number(process.env.PARDEX_PANEL_PORT || 8790);
const IS_WINDOWS = process.platform === "win32";

let config = loadConfig();
let children = [];
let lastPanelPoll = 0;
// Runs hidden (no console), so exit by itself once the panel window has been
// closed while the server is off. A running server keeps going until stopped.
const IDLE_EXIT_MS = Number(process.env.PARDEX_IDLE_EXIT_MS || 45_000);
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
  if (!config.admin_token) {
    config.admin_token = crypto.randomBytes(32).toString("hex");
    changed = true;
  }
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
  const result = IS_WINDOWS
    ? spawnSync("npm.cmd install --omit=dev --no-fund --no-update-notifier", { cwd: SERVER_DIR, stdio: "inherit", shell: true })
    : spawnSync("npm", ["install", "--omit=dev", "--no-fund"], { cwd: SERVER_DIR, stdio: "inherit" });
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
      const text = line.trim();
      // cloudflared prints a lot of INF chatter; keep only warnings/errors.
      if (!text || / INF /.test(text)) continue;
      log(text, label);
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

function tableCount() {
  return Math.min(MAX_TABLES, Math.max(1, Math.floor(Number(config.table_count) || 1)));
}

// A named Cloudflare tunnel keeps the same addresses on every start. Its
// public hostnames are set in the Cloudflare dashboard: the PARDEX address to
// http://localhost:8765 and table N's game address to http://localhost:(8766+N).
function namedTunnelHosts() {
  const host = (value) => String(value || "").trim().replace(/^[a-z]+:\/\//i, "").replace(/\/.*$/, "");
  return {
    online: host(config.tunnel_online_host),
    games: String(config.tunnel_game_hosts || "").split(",").map(host).filter(Boolean),
  };
}

function useNamedTunnel() {
  return Boolean(String(config.tunnel_token || "").trim() && namedTunnelHosts().online);
}

function openNamedTunnel(cloudflared) {
  return new Promise((resolve, reject) => {
    const child = track("Sabit tünel", spawn(cloudflared, [
      "tunnel", "--no-autoupdate", "run", "--token", String(config.tunnel_token).trim(),
    ], { stdio: ["ignore", "pipe", "pipe"], windowsHide: true }), true);
    const timer = setTimeout(() => reject(new Error("Sabit tünel 60 saniyede bağlanamadı. Tünel anahtarını kontrol et.")), 60_000);
    const onData = (chunk) => {
      if (!/Registered tunnel connection/i.test(String(chunk))) return;
      clearTimeout(timer);
      child.stdout.off("data", onData);
      child.stderr.off("data", onData);
      resolve();
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.once("exit", () => reject(new Error("Sabit tünel kapandı. Tünel anahtarını kontrol et.")));
  });
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

function startOnlineServer(gameServerUrls) {
  fs.mkdirSync(path.dirname(DATA_PATH), { recursive: true });
  track("PARDEX Online", spawn(process.execPath, ["production_server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(ONLINE_PORT),
      PARDEX_SOCIAL_DATA_PATH: DATA_PATH,
      PARDEX_GAME_SERVER_TOKEN: config.game_token,
      PARDEX_ADMIN_TOKEN: config.admin_token,
      KORSAN_GAME_SERVER_URLS: gameServerUrls.join(","),
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

// Korsan renamed its scenes; use whichever dedicated-server scene the project
// has (exported builds carry the current name).
function dedicatedServerScene(fromProject) {
  const current = "scenes/ekranlar/PardexOzelSunucu.tscn";
  const legacy = "scenes/pardex_dedicated_server.tscn";
  if (fromProject && !fs.existsSync(path.join(config.korsan_exe, current))
    && fs.existsSync(path.join(config.korsan_exe, legacy))) return `res://${legacy}`;
  return `res://${current}`;
}

// Resolves once Korsan prints PARDEX_GAME_SERVER_READY. Without this check the
// panel said "Sunucu açık" even when the game server never started, and
// players' games fell back to the LAN screen.
function startGameServer(table) {
  const port = GAME_PORT + table;
  const label = table === 0 ? "Oyun sunucusu" : `Oyun sunucusu ${table + 1}`;
  const fromProject = isProjectFolder(config.korsan_exe);
  const program = fromProject ? config.godot_exe : config.korsan_exe;
  const child = track(label, spawn(program, [
    "--headless",
    ...(fromProject ? ["--path", config.korsan_exe] : []),
    dedicatedServerScene(fromProject),
    "--",
    "--pardex-dedicated",
    `--pardex-port=${port}`,
    `--pardex-online-server=ws://127.0.0.1:${ONLINE_PORT}`,
  ], {
    cwd: fromProject ? config.korsan_exe : path.dirname(config.korsan_exe),
    env: { ...process.env, PARDEX_GAME_SERVER_TOKEN: config.game_token, PARDEX_SESSION: "*" },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  }), false);
  return new Promise((resolve, reject) => {
    let done = false;
    const finish = (error) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      clearInterval(poll);
      child.stdout?.off("data", onData);
      if (error) reject(error); else resolve();
    };
    const onData = (chunk) => {
      if (String(chunk).includes("PARDEX_GAME_SERVER_READY")) finish();
    };
    // The first headless run of a project folder imports its assets first.
    const timer = setTimeout(() => finish(new Error(
      "Oyun sunucusu 3 dakikada hazır olmadı. Kayıtlar bölümüne bak."
    )), 180_000);
    // Also accept the game port answering, in case Godot's output does not
    // reach the panel.
    const poll = setInterval(() => {
      const socket = net.connect(port, "127.0.0.1");
      socket.once("connect", () => { socket.destroy(); finish(); });
      socket.once("error", () => socket.destroy());
    }, 1000);
    child.stdout?.on("data", onData);
    child.once("exit", () => finish(new Error(
      "Oyun sunucusu başlamadı. Korsanların Hazinesi klasörünü ve Godot programını kontrol et; ayrıntı Kayıtlar'da."
    )));
    child.once("error", () => finish(new Error("Oyun sunucusu programı açılamadı (Godot yolu doğru mu?).")));
  });
}

// ------------------------------------------------------------------ address board

async function publishAddress(onlineUrl) {
  const target = String(config.publish_url || "").trim();
  if (!target.startsWith("https://")) throw new Error("Dağıtım adresi HTTPS olmalı.");
  const response = await fetch(target, {
    method: "PUT", redirect: "error", signal: AbortSignal.timeout(15000),
    headers: {"Content-Type":"application/json", Authorization:`Bearer ${config.publish_token || ""}`},
    body: JSON.stringify({online:onlineUrl}),
  });
  if (!response.ok) throw new Error(`Sunucu adresi yayınlanamadı (HTTP ${response.status}).`);
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
    if (!state.localOnly && (!config.publish_url || !config.publish_token)) {
      throw new Error("Önce dağıtım sunucusunun yayın adresini ve anahtarını kaydet (Ayarlar bölümü).");
    }
    ensureServerDependencies();
    const game = gameStatus();
    const tables = game.ok ? tableCount() : 0;
    const tableIndexes = Array.from({ length: tables }, (_, table) => table);
    let onlineUrl = `ws://127.0.0.1:${ONLINE_PORT}`;
    let gameUrls = tableIndexes.map((table) => `ws://127.0.0.1:${GAME_PORT + table}`);
    if (!state.localOnly) {
      const cloudflared = await ensureCloudflared();
      setPhase("starting", "İnternet tünelleri açılıyor...");
      if (useNamedTunnel()) {
        const hosts = namedTunnelHosts();
        if (hosts.games.length < tables) {
          throw new Error(`Sabit tünel için ${tables} oyun adresi gerekli (Ayarlar › Oyun adresleri).`);
        }
        await openNamedTunnel(cloudflared);
        onlineUrl = `wss://${hosts.online}`;
        gameUrls = hosts.games.slice(0, tables).map((host) => `wss://${host}`);
      } else {
        [onlineUrl, ...gameUrls] = await Promise.all([
          openTunnel(cloudflared, ONLINE_PORT, "PARDEX tüneli"),
          ...tableIndexes.map((table) => openTunnel(cloudflared, GAME_PORT + table, table === 0 ? "Oyun tüneli" : `Oyun tüneli ${table + 1}`)),
        ]);
      }
    }
    startOnlineServer(gameUrls);
    await waitForHealth();
    if (tables > 0) {
      setPhase("starting", "Oyun sunucusu hazırlanıyor (ilk açılış birkaç dakika sürebilir)...");
      await Promise.all(tableIndexes.map((table) => startGameServer(table)));
    }
    if (!state.localOnly) {
      setPhase("starting", "Adres arkadaşlarına duyuruluyor...");
      await publishAddress(onlineUrl);
    }
    state.onlineUrl = onlineUrl;
    state.gameUrl = gameUrls.join(", ");
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
      has_token: Boolean(config.publish_token),
      publish_url: config.publish_url || "",
      table_count: tableCount(),
      has_tunnel_token: Boolean(String(config.tunnel_token || "").trim()),
      tunnel_online_host: config.tunnel_online_host || "",
      tunnel_game_hosts: config.tunnel_game_hosts || "",
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
  // Refuse other host names (DNS rebinding) – the panel is for this PC only.
  const host = String(request.headers.host || "");
  if (host !== `127.0.0.1:${PANEL_PORT}` && host !== `localhost:${PANEL_PORT}`) {
    return sendJson(response, { error: "forbidden" }, 403);
  }
  // Only this computer's browser may drive the panel.
  const origin = request.headers.origin;
  if (origin && origin !== `http://127.0.0.1:${PANEL_PORT}` && origin !== `http://localhost:${PANEL_PORT}`) {
    return sendJson(response, { error: "forbidden" }, 403);
  }
  if (request.method === "GET" && url.pathname === "/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
    return response.end(fs.readFileSync(PANEL_PATH));
  }
  if (request.method === "GET" && url.pathname === "/api/state") {
    lastPanelPoll = Date.now();
    return sendJson(response, publicState());
  }
  if (request.method === "GET" && url.pathname === "/api/users") {
    const users = await readUsers({
      running: state.phase === "running", dataPath: DATA_PATH,
      token: config.admin_token, port: ONLINE_PORT,
    });
    return sendJson(response, users);
  }
  if (request.method === "GET" && url.pathname === "/api/bug-reports") {
    return sendJson(response, readBugReports(DATA_PATH));
  }
  if (request.method === "GET" && url.pathname === "/api/reports") {
    return sendJson(response, await readReports({
      running: state.phase === "running", dataPath: DATA_PATH,
      token: config.admin_token, port: ONLINE_PORT,
    }));
  }
  if (request.method !== "POST") return sendJson(response, { error: "not found" }, 404);

  const body = await readBody(request);
  switch (url.pathname) {
    case "/api/config": {
      if (typeof body.korsan_path === "string") config.korsan_exe = cleanPath(body.korsan_path);
      if (typeof body.godot_exe === "string") config.godot_exe = cleanPath(body.godot_exe);
      if (body.table_count !== undefined) config.table_count = Math.min(MAX_TABLES, Math.max(1, Math.floor(Number(body.table_count) || 1)));
      if (typeof body.tunnel_online_host === "string") config.tunnel_online_host = body.tunnel_online_host.trim();
      if (typeof body.tunnel_game_hosts === "string") config.tunnel_game_hosts = body.tunnel_game_hosts.trim();
      if (typeof body.tunnel_token === "string" && body.tunnel_token.trim()) {
        // "cloudflared ... --token XYZ" may be pasted whole; keep the token only.
        const parts = body.tunnel_token.trim().split(/\s+/);
        config.tunnel_token = parts[parts.length - 1];
      }
      if (body.clear_tunnel === true) config.tunnel_token = "";
      if (typeof body.publish_url === "string") {
        const url = body.publish_url.trim();
        if (url && !/^https:\/\/[^\s@]+\/online\.json$/.test(url)) return sendJson(response, {error:"HTTPS online.json adresi gerekli."}, 400);
        config.publish_url = url;
      }
      if (typeof body.publish_token === "string" && body.publish_token.trim()) {
        if (body.publish_token.trim().length < 32) return sendJson(response, {error:"Yayın anahtarı en az 32 karakter olmalı."}, 400);
        config.publish_token = body.publish_token.trim();
      }
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

// Prefer Edge/Chrome "app" mode: the panel gets its own window without tabs
// or an address bar, so it feels like a normal program.
function findAppBrowser() {
  const bases = [process.env["ProgramFiles(x86)"], process.env.ProgramFiles, process.env.LOCALAPPDATA].filter(Boolean);
  const candidates = bases.flatMap((base) => [
    path.join(base, "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(base, "Google", "Chrome", "Application", "chrome.exe"),
  ]);
  return candidates.find((candidate) => fs.existsSync(candidate)) || "";
}

function openBrowser(url) {
  if (process.env.PARDEX_NO_BROWSER) return;
  const appBrowser = IS_WINDOWS ? findAppBrowser() : "";
  if (appBrowser) {
    spawn(appBrowser, [`--app=${url}`, "--window-size=1000,940"], { detached: true, stdio: "ignore" }).unref();
  } else if (IS_WINDOWS) spawn("cmd", ["/c", "start", "", url], { detached: true, stdio: "ignore", windowsHide: true }).unref();
  else if (process.platform === "darwin") spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
}

function exitWhenIdle() {
  setInterval(() => {
    const idle = state.phase === "stopped" || state.phase === "error";
    if (idle && lastPanelPoll && Date.now() - lastPanelPoll > IDLE_EXIT_MS) {
      log("Panel kapatıldı ve sunucu kapalı; çıkılıyor.");
      process.exit(0);
    }
  }, 5000);
}

function main() {
  ensureDefaults();
  exitWhenIdle();
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

if (require.main === module) {
  const shutdown = () => stopServer().finally(() => process.exit(0));
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
  process.on("SIGHUP", shutdown);
  main();
}

module.exports = { handle };
