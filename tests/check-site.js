// Usage: node tests/check-site.js _site
// Fails if a local file referenced by index.html, sw.js (FILES) or the manifest icons is missing from the site folder.
const fs = require('node:fs');
const path = require('node:path');

const dir = process.argv[2] || '_site';
const read = f => fs.readFileSync(path.join(dir, f), 'utf8');
const refs = new Set(['index.html', 'sw.js', 'manifest.webmanifest']);

// index.html: quoted local paths like "logo.png", 'sw.js'
for (const [, p] of read('index.html').matchAll(/["'](?:\.\/)?([\w\/.-]+\.(?:png|jpg|svg|ico|js|css|html|webmanifest|json))["']/g)) {
  if (!p.includes('//')) refs.add(p);
}

// sw.js: the FILES cache list
const list = read('sw.js').match(/const FILES=\[([^\]]*)\]/);
if (!list) { console.error('FILES list not found in sw.js'); process.exit(1); }
for (const [, p] of list[1].matchAll(/'([^']*)'/g)) {
  const f = p.replace(/^\.\//, '');
  if (f) refs.add(f);
}

// manifest icons
for (const i of JSON.parse(read('manifest.webmanifest')).icons || []) refs.add(i.src.replace(/^\.\//, ''));

const missing = [...refs].filter(f => !fs.existsSync(path.join(dir, f)));
for (const f of missing) console.log(`::error::Missing in ${dir}: ${f}`);
if (missing.length) process.exit(1);
console.log(`All ${refs.size} referenced files present in ${dir}.`);
