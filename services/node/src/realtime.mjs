// Realtime (Server-Sent Events). PHP POSTs events to /publish; apps and browsers listen on
//   GET /rt/app      Authorization: Bearer <app token>   -> channel user:<id>
//   GET /rt/partner  (partner panel cookie)              -> channel partner:<id>
// PHP stays the only place that knows who a token/cookie belongs to: it is asked once per connection.
const subs = new Map(); // channel -> Set<res>
const MAX_BODY = 512 * 1024;
const MAX_LIFE_MS = 15 * 60 * 1000; // clients reconnect, so a revoked session stops listening within 15 minutes

async function channelsOf(req, kind) {
  const base = (process.env.REALTIME_AUTH_URL || process.env.APP_URL || '').replace(/\/$/, '');
  const headers = { Accept: 'application/json' };
  let path;
  if (kind === 'app') {
    if (!req.headers.authorization) return null;
    headers.Authorization = req.headers.authorization;
    path = '/api/v1/auth/channels';
  } else {
    if (!req.headers.cookie) return null;
    headers.Cookie = req.headers.cookie;
    path = '/partner/live/channels';
  }
  const res = await fetch(base + path, { headers, redirect: 'manual', signal: AbortSignal.timeout(8000) });
  if (res.status === 401 || res.status === 302) return null;
  if (!res.ok) throw new Error(`auth ${res.status}`);
  const data = await res.json();
  return Array.isArray(data.channels) ? data.channels : null;
}

export async function stream(req, res, kind) {
  let channels;
  try {
    channels = await channelsOf(req, kind);
  } catch (e) {
    console.error('[rt] auth failed:', e.message);
    res.writeHead(503).end();
    return;
  }
  if (!channels) {
    res.writeHead(401).end();
    return;
  }
  if (req.destroyed || res.destroyed) return;
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=UTF-8',
    'Cache-Control': 'no-cache, no-transform',
    'X-Accel-Buffering': 'no', // nginx: do not buffer
    Connection: 'keep-alive',
  });
  res.write('retry: 5000\nevent: ready\ndata: {}\n\n');
  for (const c of channels) {
    if (!subs.has(c)) subs.set(c, new Set());
    subs.get(c).add(res);
  }
  const beat = setInterval(() => res.write(': ping\n\n'), 20000);
  const life = setTimeout(() => res.end(), MAX_LIFE_MS);
  res.on('close', () => {
    clearInterval(beat);
    clearTimeout(life);
    for (const c of channels) {
      subs.get(c)?.delete(res);
      if (!subs.get(c)?.size) subs.delete(c);
    }
  });
}

export function publish(req, res) {
  let body = '';
  req.setEncoding('utf8');
  req.on('data', (d) => {
    body += d;
    if (body.length > MAX_BODY) req.destroy();
  });
  req.on('end', () => {
    let sent = 0;
    try {
      for (const { channels, event, data } of JSON.parse(body).events) {
        if (!/^[a-z]+$/.test(event)) continue;
        const frame = `event: ${event}\ndata: ${JSON.stringify(data ?? {})}\n\n`;
        for (const out of new Set(channels.flatMap((c) => [...(subs.get(c) ?? [])]))) {
          out.write(frame);
          sent += 1;
        }
      }
    } catch {
      res.writeHead(400).end();
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ sent }));
  });
}
