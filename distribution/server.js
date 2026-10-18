"use strict";
// Put behind your HTTPS reverse proxy. No GitHub account or API is used.
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
function createServer(root, token) {
  root = path.resolve(root);
  fs.mkdirSync(root, { recursive: true });
  return http.createServer(async (req, res) => {
    const reply = (status, data) => { res.writeHead(status, {"Content-Type":"application/json", "Cache-Control":"no-store"}); res.end(JSON.stringify(data)); };
    try {
      if (req.method === "PUT" && req.url === "/online.json") {
        const hash = v => crypto.createHash("sha256").update(v).digest();
        if (!token || token.length < 32 || !crypto.timingSafeEqual(hash(req.headers.authorization || ""), hash(`Bearer ${token}`))) return reply(403, {error:"forbidden"});
        let body = "";
        for await (const chunk of req) {
          body += chunk;
          if (body.length > 4096) return reply(413, {error:"too large"});
        }
        const data = JSON.parse(body);
        if (typeof data.online !== "string" || (data.online && !/^wss:\/\/[^\s@]+$/.test(data.online))) return reply(400, {error:"invalid address"});
        const target = path.join(root, "online.json");
        const temp = target + "." + crypto.randomUUID();
        await fs.promises.writeFile(temp, JSON.stringify({online:data.online, updated_at:new Date().toISOString()}));
        await fs.promises.rename(temp, target);
        return reply(200, {ok:true});
      }
      if (req.method !== "GET" && req.method !== "HEAD") return reply(405, {error:"method"});
      // Serve public release artifacts only; never serve credentials, source or temp files.
      const name = (req.url || "").split("?")[0];
      if (!/^\/(channel\.json|online\.json|packages\/[a-f0-9]{64}\.(zip|exe))$/.test(name)) return reply(404, {error:"not found"});
      const file = path.join(root, name.slice(1));
      const stat = await fs.promises.stat(file);
      if (!stat.isFile()) return reply(404, {error:"not found"});
      res.writeHead(200, {"Content-Type":name.endsWith(".json") ? "application/json" : "application/octet-stream", "Content-Length":stat.size, "Cache-Control":name.endsWith(".json") ? "no-cache" : "public, max-age=31536000, immutable"});
      if (req.method === "HEAD") return res.end();
      const stream = fs.createReadStream(file);
      stream.on("error", () => res.destroy());
      res.on("close", () => stream.destroy());
      stream.pipe(res);
    } catch (error) {
      if (!res.headersSent) reply(error.code === "ENOENT" ? 404 : 400, {error:"request failed"});
      else res.destroy();
    }
  });
}
if (require.main === module) {
  createServer(process.env.PARDEX_RELEASE_DIR || path.join(__dirname, "public"), process.env.PARDEX_PUBLISH_TOKEN || "")
    .listen(Number(process.env.PORT || 8780), process.env.HOST || "127.0.0.1", () => console.log("PARDEX distribution ready"));
}
module.exports = {createServer};
