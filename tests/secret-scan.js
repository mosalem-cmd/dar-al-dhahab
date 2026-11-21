// Secret scan over tracked files. Prints file + kind only, never the value.
// The Supabase anon key (a JWT with role "anon") is allowed by design.
const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const self = path.relative(root, __filename);
const files = execSync('git ls-files -z', { cwd: root }).toString().split('\0').filter(Boolean);

const rules = [
  ['Supabase secret key', /sb_secret_[A-Za-z0-9_-]{10,}/],
  ['private key block', /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ['GitHub token', /\bgh[pousr]_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}/],
];

// JWT whose payload says role = service_role
function hasServiceRoleJwt(text) {
  for (const [, payload] of text.matchAll(/eyJ[A-Za-z0-9_-]+\.(eyJ[A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+/g)) {
    try {
      if (JSON.parse(Buffer.from(payload, 'base64url').toString()).role === 'service_role') return true;
    } catch { /* not a JWT */ }
  }
  return false;
}

let found = 0;
for (const f of files) {
  if (f === self) continue;
  const buf = fs.readFileSync(path.join(root, f));
  if (buf.includes(0)) continue; // skip binaries (png...)
  const text = buf.toString('utf8');
  const hits = rules.filter(([, re]) => re.test(text)).map(([k]) => k);
  if (hasServiceRoleJwt(text)) hits.push('service_role key');
  for (const k of hits) { console.log(`::error file=${f}::Possible ${k}`); found++; }
}

if (found) { console.error(`Secret scan failed: ${found} finding(s).`); process.exit(1); }
console.log(`Secret scan OK (${files.length} files).`);
