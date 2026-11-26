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

// v2.6.0: المنصة للمطاحن: الصفحات الإجمالية لا تعرض مجموع ذهب الزبون ولا صافيه
test('aggregate pages never show customer gold totals or net', () => {
  const html = read('index.html');
  const body = name => {   // نص الدالة كاملًا (حتى القوس المطابق)
    const st = html.indexOf(`function ${name}(`); assert.ok(st > 0, name + ' not found');
    let d = 0; for (let i = html.indexOf('{', st); i < html.length; i++) { if (html[i] === '{') d++; else if (html[i] === '}' && --d === 0) return html.slice(st, i + 1); }
  };
  const bad = /goldTotal|\bi\.net\b|\bc\.net\b|\bc\.gold\b|\.amts\b|sumGold|sumNet|kSales|kNet|'net'\)/;
  for (const f of ['openHome', 'renderList', 'openRep', 'openCust', 'openProf', 'admOverview'])
    assert.doesNotMatch(body(f), bad, f + ' shows customer gold/net');
  // تفاصيل حساب المطحنة عند المشرف
  const adm = html.slice(html.indexOf('const ncust='), html.indexOf("t('recentInv')") + 600);
  assert.doesNotMatch(adm, /i\.net|\bnet=/, 'admin detail shows customer net');
});

// v2.6.1: دليل الاستخدام يطابق سلوك التطبيق الحالي (لا عبارات قديمة متناقضة)
test('in-app guide has no outdated statements', () => {
  const html = read('index.html');
  const guide = html.slice(html.indexOf('const HOME={'), html.indexOf('};', html.indexOf('const HOME={')));
  for (const stale of ['ضع علامة «الحساب مسدَّد»', 'الزر الدائري في أسفل الشاشة يفتح دفتر', 'الحذف نهائي', 'على هذا الجهاز فقط', 'والمبيعات، والتكاليف', 'وحصص الشركاء',
    'Cochez « Compte réglé »', 'Le bouton rond en bas ouvre', 'La suppression est définitive', 'Sur cet appareil uniquement', 'ventes, frais par ligne'])
    assert.ok(!guide.includes(stale), 'outdated guide text: ' + stale);
});

// v2.6.2: تغيير رقم الدخول: الدالة محمية والواجهة تستدعيها لحساب المطحنة فقط
test('change login phone: guarded SQL function and a mill-only settings page', () => {
  const sql = read('6_change_phone.sql');
  assert.match(sql, /change_phone\(p_token text, p_pass text, p_new_phone text\)[\s\S]*public\._acct\(p_token\)/);
  assert.match(sql, /a\.role <> 'mill' then raise exception 'E_ADMIN_PHONE'/, 'admins excluded');
  assert.match(sql, /extensions\.crypt\(coalesce\(p_pass,''\), a\.pass_hash\)/, 'current password checked');
  assert.match(sql, /public\.admin_phones where phone = ph/, 'admin numbers reserved');
  assert.match(sql, /delete from public\.sessions where account_id = a\.id and token <> p_token/, 'other devices signed out');
  assert.match(sql, /security definer set search_path to ''/);
  const html = read('index.html');
  assert.match(html, /function openPhone\(keep\)[\s\S]*rpc\('change_phone'/);
  assert.match(html, /sess\.me\.role!=='admin'\?`<button data-go="phone">/, 'button hidden for admins');
});
