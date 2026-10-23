"use strict";
// Sunucu Paneli › Yayınla: jobs run the tools\*.ps1 scripts with -Panel and
// show their output. Uses stand-in scripts in a temporary folder, never the
// real publish scripts. Needs PowerShell (pwsh; PARDEX_POWERSHELL overrides).
const assert = require("assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

process.env.PARDEX_POWERSHELL = process.env.PARDEX_POWERSHELL || "pwsh";
const { _test: host } = require("./pardex_host");

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function finished() {
  for (let i = 0; i < 300 && host.job.running; i++) await wait(50);
  assert.equal(host.job.running, false, "job should finish");
  return host.job;
}

async function run() {
  if (spawnSync(process.env.PARDEX_POWERSHELL, ["-NoProfile", "-Command", "exit 0"]).status !== 0) {
    console.log("Host publish job test skipped: PowerShell not found");
    return;
  }
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-job-"));
  const tools = path.join(folder, "tools");
  fs.mkdirSync(tools);
  fs.mkdirSync(path.join(folder, "scripts"));
  fs.writeFileSync(path.join(folder, "scripts", "main.gd"), 'const APP_VERSION := "0.4.2"\n');
  // A stand-in for each script: reports what the panel passed, then exits.
  fs.writeFileSync(path.join(tools, "yayinla.ps1"),
    'param([string]$Version = "", [switch]$Panel)\n[Console]::OutputEncoding = [Text.Encoding]::UTF8\nWrite-Host "surum=$Version panel=$Panel"\nWrite-Host "Yayınlandı"\nexit 0\n');
  fs.writeFileSync(path.join(tools, "oyun_yayinla.ps1"),
    'param([string]$InputPath = "", [switch]$Panel)\n$a = [IO.File]::ReadAllText($InputPath, [Text.Encoding]::UTF8) | ConvertFrom-Json\nWrite-Host "oyun=$($a.id) baslik=$($a.title)"\nWrite-Host "HATA: deneme"\nexit 1\n');
  fs.writeFileSync(path.join(tools, "ag_testi.ps1"), 'param([switch]$Panel)\nStart-Sleep -Milliseconds 800\nWrite-Host "ag tamam"\n');
  // One game written as a single object with a BOM, as PowerShell 5 may write it.
  fs.writeFileSync(path.join(folder, "release.local.json"),
    "\uFEFF" + JSON.stringify({ games: { id: "korsanlar", title: "Korsanlar", version: "1.2.0", genres: ["Macera", "Strateji"], screenshots: ["a.png", "b.png"] } }));
  host.setPublishPaths(folder);
  try {
    const release = host.releaseInfo();
    assert.equal(release.launcher_version, "0.4.2");
    assert.deepEqual(release.games.map((game) => [game.id, game.genres, game.screenshots]), [["korsanlar", "Macera, Strateji", "a.png;b.png"]]);

    // Bad input is refused before anything runs.
    assert.match(host.startJob("launcher", { version: "1.x" }), /1\.2\.3/);
    assert.match(host.startJob("game", { game: { id: "oyun", version: "1.0.0" } }), /proje klasörünü/);
    assert.match(host.startJob("game", { game: { id: "Kötü Ad", version: "1.0.0", project: "C:\\oyun" } }), /kimliği/);
    assert.match(host.startJob("sil", {}), /Bilinmeyen/);
    assert.equal(host.job.kind, "", "nothing started");

    assert.equal(host.startJob("launcher", { version: "0.4.3" }), "");
    assert.match(host.startJob("network", {}), /sürüyor/, "one job at a time");
    let job = await finished();
    assert.equal(job.ok, true);
    assert.deepEqual(job.lines, ["surum=0.4.3 panel=True", "Yayınlandı"]);

    assert.equal(host.startJob("game", { game: { id: "yeni-oyun", title: "Yeni Oyun ğüş", version: "1.0.0", project: folder } }), "");
    job = await finished();
    assert.equal(job.ok, false, "a failing script is reported as failed");
    assert.deepEqual(job.lines, ["oyun=yeni-oyun baslik=Yeni Oyun ğüş", "HATA: deneme"]);
    assert.equal(fs.readdirSync(os.tmpdir()).filter((name) => name.startsWith("pardex-oyun-")).length, 0, "answers file removed");

    // Ayarlar writes the shared settings file (with a BOM for PowerShell 5) without losing other keys.
    fs.writeFileSync(path.join(tools, "yayinla.local.json"), "\uFEFF" + JSON.stringify({ godot: "C:\\Godot.exe", extra: 1 }));
    host.writePublishSettings({ account: "0123456789abcdef0123456789abcdef" });
    assert.ok(fs.readFileSync(path.join(tools, "yayinla.local.json"), "utf8").startsWith("\uFEFF"));
    assert.deepEqual(host.readPublishSettings(), { godot: "C:\\Godot.exe", extra: 1, account: "0123456789abcdef0123456789abcdef" });
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
  console.log("Host publish job test passed: input checks, one job at a time, output and result shown, answers file removed, shared settings kept");
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
