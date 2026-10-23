"use strict";
const assert = require("assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const http = require("http");
const { once } = require("events");
const { readUsers } = require("./user_admin");
const { handle } = require("./pardex_host");

async function run() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pardex-host-users-"));
  const dataPath = path.join(dir, "social.json");
  const server = http.createServer((req, res) => {
    assert.equal(req.url, "/admin/users");
    assert.equal(req.headers.authorization, "Bearer test-only");
    res.end(JSON.stringify({ total: 1, online: 1, users: [] }));
  });
  try {
    async function panelRequest(headers) {
      const response = { writeHead(status) { this.status = status; }, end(body) { this.body = JSON.parse(body); } };
      await handle({ method: "GET", url: "/api/users", headers }, response);
      return response;
    }
    const localHost = `127.0.0.1:${process.env.PARDEX_PANEL_PORT || 8790}`;
    assert.equal((await panelRequest({ host: "attacker.example" })).status, 403);
    assert.equal((await panelRequest({ host: localHost, origin: "https://attacker.example" })).status, 403);
    assert.equal((await readUsers({ dataPath })).total, 0);
    fs.writeFileSync(dataPath, JSON.stringify({ accounts: { px_fixture: {
      display_name: "<img src=x onerror=alert(1)>", created_at: 123,
      friends: ["px_friend"], recovery_hash: "private", avatar: "private",
    } }, identity_aliases: { private: "px_fixture" }, conversations: { private: "private" } }));
    const users = await readUsers({ dataPath });
    assert.equal(users.total, 1);
    assert.equal(users.online, 0);
    assert.equal(users.users[0].friend_count, 1);
    assert.equal(JSON.stringify(users).includes("private"), false);
    fs.writeFileSync(dataPath, "broken");
    await assert.rejects(readUsers({ dataPath }), /okunamadı/);
    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    assert.equal((await readUsers({ running: true, port: server.address().port, token: "test-only" })).online, 1);
    // Check the inline panel script parses without starting browser timers.
    const html = fs.readFileSync(path.join(__dirname, "panel.html"), "utf8");
    const vm = require("vm");
    const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
    new vm.Script(script);
    class Element {
      constructor() { this.textContent = ""; this.value = ""; this.children = []; }
      append(...children) { this.children.push(...children); }
      replaceChildren(...children) { this.children = children; }
      addEventListener() {}
    }
    const elements = new Map();
    const document = {
      getElementById(id) { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); },
      createElement() { return new Element(); }, createDocumentFragment() { return new Element(); },
      querySelectorAll() { return []; },
    };
    const context = vm.createContext({ document });
    vm.runInContext(script.slice(0, script.lastIndexOf("\nrefresh();")), context);
    vm.runInContext(`userData = ${JSON.stringify(users)}; renderUsers();`, context);
    const rows = elements.get("userRows").children[0].children;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].children[0].textContent, users.users[0].display_name, "user markup must remain plain text");
    assert.equal(elements.get("statUsers").textContent, 1);
    elements.get("userSearch").value = "missing";
    vm.runInContext("renderUsers()", context);
    assert.equal(elements.get("userRows").children[0].children.length, 0);
    console.log("Host user list smoke test passed");
  } finally { server.close(); fs.rmSync(dir, { recursive: true, force: true }); }
}
run().catch((error) => { console.error(error); process.exitCode = 1; });
