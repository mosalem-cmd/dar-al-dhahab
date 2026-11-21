// Checks for sw.js and manifest.webmanifest.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const read = f => fs.readFileSync(path.join(__dirname, '..', f), 'utf8');

test('sw.js cache name is dar-vX.Y.Z', () => {
  assert.match(read('sw.js'), /const VERSION='dar-v\d+\.\d+\.\d+';/);
});

test('manifest is valid JSON with name, icons, start_url', () => {
  const m = JSON.parse(read('manifest.webmanifest'));
  assert.ok(m.name, 'name missing');
  assert.ok(m.start_url, 'start_url missing');
  assert.ok(Array.isArray(m.icons) && m.icons.length > 0, 'icons missing');
});
