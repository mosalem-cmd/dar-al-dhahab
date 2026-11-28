// اختبارات المساعدة (v2.5.0): الزر في صفحة الدخول، ومحتوى المشاكل، والصور، وقناة التواصل.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');
const html = read('index.html');

// تحميل help.js في صندوق vm بلا DOM (يُصدّر DarHelp ولا يشغّل الواجهة)
const ctx = vm.createContext({});
vm.runInContext(read('help.js'), ctx);
const H = ctx.DarHelp;
const plain = x => JSON.parse(JSON.stringify(x));   // كائنات الصندوق من عالم مختلف

test('help button exists outside the pages, so it shows on the login page', () => {
  const fab = html.indexOf('id="helpFab"');
  assert.ok(fab > 0, '#helpFab missing');
  const mainStart = html.indexOf('<main>'), mainEnd = html.indexOf('</main>');
  assert.ok(fab < mainStart || fab > mainEnd, '#helpFab must not be inside <main> (views)');
  assert.ok(!/\.authv[^{]*(#helpFab|\.helpfab)[^{]*\{[^}]*display\s*:\s*none/.test(html), 'help button hidden on the login page');
  assert.match(html, /<script src="help\.js"><\/script>/);
  assert.match(html, /\.helpfab\{[^}]*width:\s*(4[4-9]|[5-9]\d)px/, 'touch target must be at least 44px');
});

test('every problem has an id, titles in both languages and at least one step', () => {
  const ids = H.HELP.map(p => p.id);
  assert.equal(new Set(ids).size, ids.length, 'duplicate ids');
  for (const req of ['code', 'forgot', 'sub', 'update', 'invSave', 'invShow', 'offline'])
    assert.ok(ids.includes(req), 'missing required problem: ' + req);
  for (const p of H.HELP) {
    assert.ok(p.t.ar && p.t.fr, p.id + ': title');
    assert.ok(H.CATS[p.cat], p.id + ': category');
    assert.ok(Array.isArray(p.steps) && p.steps.length >= 1, p.id + ': needs at least one step');
    for (const s of p.steps) assert.ok(s.ar && s.fr, p.id + ': step text in both languages');
    assert.ok(p.steps.some(s => s.img), p.id + ': needs at least one illustration');
  }
});

test('the update problem no longer suggests deleting site data', () => {
  const up = plain(H.HELP.find(p => p.id === 'update'));
  assert.ok(!JSON.stringify(up).match(/حذف بيانات الموقع|supprim/i));
});

test('every illustration is a valid themed SVG with fake data only', () => {
  for (const p of H.HELP) for (const s of p.steps) if (s.img) for (const l of ['ar', 'fr']) {
    assert.ok(H.SCREENS.includes(s.img[0]), p.id + ': unknown screen ' + s.img[0]);
    const out = H.svg(s.img[0], s.img[1], l);
    assert.ok(out.startsWith('<svg') && out.endsWith('</svg>'), p.id + ': svg');
    assert.match(out, /var\(--(card|bg|ink)\)/, 'colours must come from theme variables');
    assert.match(out, /class="hlp"/, p.id + ': tap position must be highlighted');
    // النص الظاهر في الصورة: لا رقم هاتف حقيقي (8 أرقام فأكثر) إلا الرقم الوهمي 22 00 00 00
    const shown = [...out.matchAll(/<text[^>]*>([^<]*)<\/text>/g)].map(m => m[1]).join(' ').replace(/22 00 00 00/g, '');
    assert.ok(!/\d{8}/.test(shown.replace(/[\s,.\-]/g, '')), p.id + ': no real phone numbers in images');
  }
});

test('contact channel: constant, in-app fallback for signed-in users, code giver for others', () => {
  assert.deepEqual(Object.keys(plain(H.ADMIN_CONTACT)).sort(), ['email', 'whatsapp']);
  const empty = { whatsapp: '', email: '' };
  assert.match(H.contactHtml(true, 'ar', empty), /الشكاوى والملاحظات/);
  assert.match(H.contactHtml(false, 'ar', empty), /الجهة التي أعطتك رمز الاعتماد/);
  assert.doesNotMatch(H.contactHtml(false, 'ar', empty), /الشكاوى والملاحظات/);
  assert.match(H.contactHtml(false, 'fr', empty), /code d’approbation/);
  assert.match(H.contactHtml(true, 'ar', { whatsapp: '+222 0000 0000', email: '' }), /https:\/\/wa\.me\/22200000000/);
  assert.match(H.contactHtml(true, 'ar', { whatsapp: '', email: 'x@example.com' }), /mailto:x@example\.com/);
  for (const id of ['forgot', 'sub', 'update']) assert.ok(H.HELP.find(p => p.id === id).steps.some(s => s.contact), id + ': must show the contact channel');
});

test('phase-2 ticket structure is built without any server call', () => {
  const t = plain(H.buildTicket('sub', 'x'.repeat(600), { lang: 'fr', version: '2.5.0', view: 'home' }));
  assert.equal(t.problemId, 'sub');
  assert.equal(t.text.length, 500);
  assert.equal(t.lang, 'fr');
  assert.equal(t.appVersion, '2.5.0');
  // الاتصال الوحيد المسموح: rpc('help_request') ولمن له جلسة فقط (canSend)
  const src = read('help.js');
  assert.ok(!/fetch\(|XMLHttpRequest/.test(src), 'no direct network calls');
  assert.deepEqual([...src.matchAll(/rpc\('([a-z_]+)'/g)].map(m => m[1]), ['help_request']);
  assert.match(src, /if \(!canSend\(\)\) \{[^}]*return; \}/, 'must not send without a session');
});

test('phase 2 is enabled: signed-in users send, the login page never does', () => {
  assert.match(read('help.js'), /const HELP_SEND_ENABLED = true;/, 'sending switch must be on');
  const load = pre => { const c = vm.createContext({}); vm.runInContext(pre, c); vm.runInContext(read('help.js'), c); return c.DarHelp; };
  assert.equal(load('var sess = {token:"t"}; function rpc(){}').canSend(), true, 'signed in: sends');
  assert.equal(load('var sess = null; function rpc(){}').canSend(), false, 'login page / no session');
  assert.equal(load('var sess = {token:"t"};').canSend(), false, 'no rpc available');
  assert.match(read('index.html'), /admCache\.help=await rpc\('admin_help_stats'/, 'admin card requests admin_help_stats');
});

test('phase 2 SQL: session required, rate-limited, help kind allowed', () => {
  const sql = read('4_help_requests.sql');
  assert.match(sql, /help_request\(p_token text[\s\S]*public\._acct\(p_token\)/);
  assert.match(sql, /n >= 5 then raise exception 'E_RATE'/);
  assert.match(sql, /'complaint','note','suggestion','help'/);
  assert.match(sql, /admin_help_stats[\s\S]*public\._admin\(p_token\)/);
  assert.doesNotMatch(sql, /grant [^;]* to (authenticated|public)/i);
});

test('service worker caches help.js', () => {
  const sw = read('sw.js');
  assert.match(sw, /'\.\/help\.js'/);
  assert.match(sw, /const VERSION='dar-v2\.10\.5'/);
});

test('dark-mode logo: transparent version used in dark mode only, phone icon unchanged', () => {
  assert.ok(fs.existsSync(path.join(root, 'logo-dark.png')), 'logo-dark.png missing');
  assert.match(html, /\[data-theme=dark\] img\.logo[^{]*\{[^}]*content:url\(logo-dark\.png\)/);
  assert.doesNotMatch(html.replace(/\[data-theme=dark\][^{]*\{[^}]*\}/g, ''), /logo-dark\.png/, 'light mode must keep logo.png');
  assert.match(read('sw.js'), /'\.\/logo-dark\.png'/);
  const icons = JSON.parse(read('manifest.webmanifest')).icons.map(i => i.src);
  assert.ok(!icons.some(s => /logo-dark/.test(s)), 'manifest icons must not change');
});

// v2.6.5: نافذة المساعدة: شاشة واحدة في كل مرة، بلا تراكم رسائل
test('help chat shows one screen at a time and never accumulates messages', () => {
  const src = read('help.js');
  assert.match(src, /function clear\(\) \{ clearTimeout\(timer\); gen\+\+;/, 'clear() resets timer and bumps the generation');
  for (const fn of ['showProblem', 'solved', 'helpSubmit', 'home'])
    assert.match(src.slice(src.indexOf('function ' + fn)), /^[\s\S]{0,260}clear\(\)/, fn + ' must clear the log first');
  assert.doesNotMatch(src, /add\(UI\[cur\(\)\]\.(solved|persist), 'me'\)|add\(esc\(v\), 'me'\)|add\(esc\(p\.t\[l\]\), 'me'\)/, 'no echo bubbles that pile up');
  assert.match(src, /if \(!chat \|\| my !== gen\) return;/, 'late replies must not touch a newer screen');
  assert.match(src, /clearTimeout\(timer\); gen\+\+; chat\.remove\(\)/, 'closing cancels pending timers');
  assert.match(src, /restoreText\(ticket\.text\)/, 'typed text is restored when sending fails');
  assert.doesNotMatch(src, /backLater\(6000\)/, 'no timed dismissal of the confirmation with its links');
  assert.match(src, /function focusScreen\(\)/, 'focus moves to the new screen');
  assert.doesNotMatch(src, /class="hlog" aria-live/, 'whole log is not an assertive live region');
  for (const l of ['ar', 'fr']) assert.ok(H.UI[l].back && H.UI[l].gladShort, l + ': back / glad strings');
});

// v2.10.4: إرسال طلب المساعدة: مهلة، إعادة محاولة، وطابور بلا اتصال يُرسل مرة واحدة
test('help request: timeout + retry, offline queue sent exactly once', () => {
  const src = read('help.js');
  assert.match(src, /SEND_MS = 15000/, 'time limit for sending');
  assert.match(src, /data-hretry/, 'retry button');
  assert.match(src, /restoreText\(ticket\.text\)/, 'typed text kept on failure');
  assert.match(src, /if \(isOffline\(\)\) \{ queue\(ticket\)/, 'offline: saved on the phone');
  assert.match(src, /qSet\(q\.filter\(x => x\.id !== item\.id\)\);\s*\/\/ سحب قبل الإرسال/, 'item taken out before sending (no double send across windows)');
  assert.match(src, /x\.acc === acc/, 'queue bound to the account');
  assert.match(read('index.html'), /localStorage\.removeItem\('dar-help-queue'\)[\s\S]*localStorage\.removeItem\('dar-help-queue'\)/, 'queue cleared on logout and on lost session');
  assert.match(src, /qSet\(q\.slice\(-20\)\)/, 'queue size bounded');
  assert.match(src, /if \(flushing \|\| !canSend\(\)/, 'one sender at a time');
  for (const l of ['ar', 'fr']) assert.ok(H.UI[l].retryMsg && H.UI[l].retry && H.UI[l].queued, l + ': strings');
});
