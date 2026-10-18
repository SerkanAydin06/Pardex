"use strict";
const assert = require('assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {once} = require('events');
const {createServer} = require('./server');
(async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pardex-dist-'));
  const token = 'test-only-'.repeat(5);
  const server = createServer(root, token);
  try {
    fs.writeFileSync(path.join(root,'channel.json'), '{"schema":1,"games":[]}');
    fs.writeFileSync(path.join(root,'secret.txt'), 'must not be served');
    server.listen(0,'127.0.0.1'); await once(server,'listening');
    const base = `http://127.0.0.1:${server.address().port}`;
    assert.equal((await fetch(base+'/channel.json')).status,200);
    assert.equal((await fetch(base+'/secret.txt')).status,404);
    assert.equal((await fetch(base+'/online.json',{method:'PUT',body:'{}'})).status,403);
    const publish = body => fetch(base+'/online.json',{method:'PUT',headers:{authorization:`Bearer ${token}`},body:JSON.stringify(body)});
    assert.equal((await publish({online:'file:///tmp/private'})).status,400);
    assert.equal((await publish({online:'wss://fixture.example'})).status,200);
    assert.equal((await (await fetch(base+'/online.json')).json()).online,'wss://fixture.example');
    assert.equal((await publish({online:''})).status,200);
    assert.equal((await (await fetch(base+'/online.json')).json()).online,'');
    console.log('Distribution HTTP smoke passed');
  } finally {server.closeAllConnections(); await new Promise(r=>server.close(r)); fs.rmSync(root,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
