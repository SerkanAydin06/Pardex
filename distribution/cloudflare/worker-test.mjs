import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import worker from './worker.mjs';
globalThis.crypto ??= webcrypto;
const objects = new Map([['channel.json', '{"schema":1}']]);
const env = {PUBLISH_TOKEN:'x'.repeat(40), RELEASES:{
  async put(key, value) { objects.set(key, value); },
  async get(key) { const value = objects.get(key); return value === undefined ? null : {body:value, size:Buffer.byteLength(value), httpEtag:'"test"'}; },
  async head(key) { return this.get(key); },
}};
const call = (path, method='GET', body, token) => worker.fetch(new Request('https://example.workers.dev'+path, {
  method, body, headers:token ? {Authorization:`Bearer ${token}`} : {},
}), env);
assert.equal(await (await call('/channel.json')).text(), '{"schema":1}');
assert.equal((await call('/channel.json')).headers.get('cache-control'), 'no-store');
assert.equal(await (await call('/channel.json','HEAD')).text(), '');
assert.equal((await call('/.env')).status, 404);
assert.equal((await call('/online.json')).status, 404);
assert.equal((await call('/channel.json','PUT','{}',env.PUBLISH_TOKEN)).status,405);
assert.equal((await call('/online.json','PUT','{}','wrong')).status,403);
assert.equal((await call('/online.json','PUT','x'.repeat(4097),env.PUBLISH_TOKEN)).status,413);
for (const online of ['http://example.com','wss://user:password@example.com','wss://','wss://example.com/#secret']) {
  assert.equal((await call('/online.json','PUT',JSON.stringify({online}),env.PUBLISH_TOKEN)).status,400);
}
for (const online of ['wss://game.example.com','']) {
  assert.equal((await call('/online.json','PUT',JSON.stringify({online}),env.PUBLISH_TOKEN)).status,200);
  assert.equal((await (await call('/online.json')).json()).online,online);
}
const image = '/packages/'+'b'.repeat(64)+'.png';
objects.set(image.slice(1), 'png-bytes');
assert.equal((await call(image)).headers.get('content-type'), 'image/png');
assert.equal((await call('/packages/'+'b'.repeat(64)+'.gif')).status, 404);
const key = '/packages/'+ 'a'.repeat(64)+'.zip';
objects.set(key.slice(1), 'binary-package');
assert.equal(await (await call(key)).text(), 'binary-package');
assert.match((await call(key)).headers.get('cache-control'), /immutable/);
console.log('R2 Worker routing, downloads, authentication and address validation passed.');
