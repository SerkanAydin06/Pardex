// Public release downloads; only the PC host can update online.json.
const json = (status, data) => new Response(JSON.stringify(data), {
  status, headers: {'Content-Type':'application/json', 'Cache-Control':'no-store'},
});
async function authorized(request, token) {
  if (typeof token !== 'string' || token.length < 32) return false;
  const hash = value => crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  const [a, b] = await Promise.all([hash(request.headers.get('Authorization') || ''), hash(`Bearer ${token}`)]);
  const aa = new Uint8Array(a), bb = new Uint8Array(b);
  let difference = 0;
  for (let i = 0; i < aa.length; i++) difference |= aa[i] ^ bb[i];
  return difference === 0;
}
async function readAddress(request) {
  const reader = request.body?.getReader();
  const chunks = [];
  let length = 0;
  if (reader) {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > 4096) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder().decode(bytes));
}
export default {
  async fetch(request, env) {
    const key = new URL(request.url).pathname.slice(1);
    if (!/^(channel\.json|online\.json|packages\/[a-f0-9]{64}\.(zip|exe))$/.test(key)) return json(404, {error:'not found'});
    if (request.method === 'PUT' && key === 'online.json') {
      if (!await authorized(request, env.PUBLISH_TOKEN)) return json(403, {error:'forbidden'});
      let data;
      try { data = await readAddress(request); } catch { return json(400, {error:'invalid JSON'}); }
      if (data === null) return json(413, {error:'too large'});
      if (typeof data?.online !== 'string') return json(400, {error:'invalid address'});
      if (data.online) {
        try {
          const url = new URL(data.online);
          if (url.protocol !== 'wss:' || !url.hostname || url.username || url.password || url.hash || /\s/.test(data.online)) throw Error();
        } catch { return json(400, {error:'invalid address'}); }
      }
      await env.RELEASES.put(key, JSON.stringify({online:data.online, updated_at:new Date().toISOString()}), {httpMetadata:{contentType:'application/json'}});
      return json(200, {ok:true});
    }
    if (!['GET','HEAD'].includes(request.method)) return json(405, {error:'method'});
    const object = await env.RELEASES[request.method === 'HEAD' ? 'head' : 'get'](key);
    if (!object) return json(404, {error:'not found'});
    return new Response(request.method === 'HEAD' ? null : object.body, {headers:{
      'Content-Type':key.endsWith('.json') ? 'application/json' : 'application/octet-stream',
      'Content-Length':String(object.size), 'ETag':object.httpEtag,
      'X-Content-Type-Options':'nosniff',
      'Cache-Control':key.endsWith('.json') ? 'no-store' : 'public, max-age=31536000, immutable',
    }});
  },
};
