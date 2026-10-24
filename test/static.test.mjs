import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createApp } from '../server.mjs';

test('Flutter assets and API share an origin; legacy and binary MIME types still work', async () => {
  const dir = await mkdtemp(path.join(tmpdir(), 'shotrelay-static-'));
  const webDir = path.join(dir, 'web');
  await mkdir(webDir);
  await writeFile(path.join(webDir, 'index.html'), '<html>Flutter fixture</html>');
  await writeFile(path.join(webDir, 'main.dart.js'), '/* fixture */');
  await writeFile(path.join(webDir, 'renderer.wasm'), Buffer.from([0,97,115,109]));
  const server = await createApp({ dataDir: path.join(dir, 'data'), webDir });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const home = await fetch(base);
    assert.match(await home.text(), /Flutter fixture/);
    const js = await fetch(base + '/main.dart.js');
    assert.match(js.headers.get('content-type'), /javascript/);
    const wasm = await fetch(base + '/renderer.wasm');
    assert.equal(wasm.headers.get('content-type'), 'application/wasm');
    assert.equal((await fetch(base + '/api/state')).status, 401);
    const legacy = await fetch(base + '/legacy');
    assert.match(await legacy.text(), /ShotRelay MVP/);
    assert.equal((await fetch(base + '/app.js')).status, 200);
    assert.equal((await fetch(base + '/style.css')).status, 200);
    assert.equal((await fetch(base + '/missing-file')).status, 404);
    assert.equal((await fetch(base + '/%2e%2e%2fstate.json')).status, 403);
  } finally {
    await new Promise(r => server.close(r));
    await rm(dir, { recursive: true, force: true });
  }
});
