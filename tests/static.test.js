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
