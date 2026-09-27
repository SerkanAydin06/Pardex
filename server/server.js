const http = require("http");

// server_core owns the HTTP server. Decorate the bootstrap once so CI can verify
// which Git commit Railway is actually serving before testing the live protocol.
const originalCreateServer = http.createServer.bind(http);
http.createServer = (requestListener) => originalCreateServer((req, res) => {
  if (req.url === "/deployment") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      commitSha: String(process.env.RAILWAY_GIT_COMMIT_SHA || "").trim(),
      deploymentId: String(process.env.RAILWAY_DEPLOYMENT_ID || "").trim(),
    }));
    return;
  }
  requestListener(req, res);
});

require("./server_core");
