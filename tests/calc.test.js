// Tests for the invoice math in index.html (node:test, no dependencies).
const test = require('node:test');
const assert = require('node:assert/strict');
const plain = x => JSON.parse(JSON.stringify(x));
const { calc, num, fmt, dashStats, reportStats, repSeries, buildSettings, plural, NOUN } = require('./extract');

test('baseline invoice', () => {
  const r = calc({
    grams: '100', gramPrice: '3000', tons: '2',
    costs: [{ qty: '2', unit: '15000' }, { qty: '', unit: '10000' }], // empty qty counts as 1
    pcts: [{ pct: '50' }, { pct: '25' }, { pct: '15' }, { pct: '10' }],
  });
  assert.equal(r.gold, 300000);
  assert.equal(r.costsTotal, 40000);
  assert.equal(r.net, 260000);
  assert.equal(r.recov, 50);
  assert.deepEqual([...r.amts], [130000, 65000, 39000, 26000]);
  assert.equal(r.pctSum, 100);
});

test('Arabic digits are parsed', () => {
  assert.equal(num('١٢٫٥'), 12.5);
  assert.equal(num('٣٠٠,٠٠٠'), 300000);
  assert.equal(calc({ grams: '١٢٫٥', gramPrice: '٢٨٥٠' }).gold, 35625);
});

test('12.5 g x 2850 = 35625', () => {
  assert.equal(calc({ grams: '12.5', gramPrice: '2850' }).gold, 35625);
});

test('negative net does not crash', () => {
  const r = calc({
    grams: '12', gramPrice: '3000', tons: '1',
    costs: [{ qty: '1', unit: '40000' }],
    pcts: [{ pct: '50' }, { pct: '50' }],
  });
  assert.equal(r.net, -4000);
  assert.deepEqual([...r.amts], [-2000, -2000]);
  assert.equal(fmt(r.net), '-4,000');
});

test('tons <= 0 gives recovery 0', () => {
  assert.equal(calc({ grams: '100', tons: '0' }).recov, 0);
  assert.equal(calc({ grams: '100', tons: '-1' }).recov, 0);
  assert.equal(calc({ grams: '100' }).recov, 0);
});

// ---- v2.4.2: ربح المطحنة والمسدَّد والمتبقي (من التكاليف فقط، لا من صافي الزبون) ----
const inv = (extra = {}) => ({
  grams: '100', gramPrice: '3000', tons: '2',
  costs: [{ qty: '2', unit: '15000' }, { qty: '', unit: '10000' }], // التكاليف = 40000
  pcts: [{ pct: '100' }], ...extra,
});

test('paid amount: remaining comes from costs, not from customer net', () => {
  const r = calc(inv({ paidAmt: '25000' }));
  assert.equal(r.net, 260000);        // صافي الزبون لا يتغير
  assert.equal(r.paid, 25000);
  assert.equal(r.remaining, 15000);   // 40000 - 25000
});

test('legacy invoices (no paidAmt): paid=true means costs fully paid', () => {
  assert.equal(calc(inv({ paid: true })).remaining, 0);
  assert.equal(calc(inv({ paid: false })).remaining, 40000);
});

test('overpayment never gives a negative remaining', () => {
  const r = calc(inv({ paidAmt: '50000' }));
  assert.equal(r.remaining, 0);
  assert.equal(r.paid, 50000);
});

test('dashboard: profit = billed costs - mill expenses', () => {
  const d = dashStats([{ costsTotal: 40000, net: 260000, paidAmt: 25000 }], 8000);
  assert.equal(d.billed, 40000);
  assert.equal(d.profit, 32000);      // 40000 - 8000
  assert.equal(d.paid, 25000);
  assert.equal(d.remaining, 15000);
  assert.equal(d.unpaidCount, 1);
});

test('dashboard: legacy paid invoice, several invoices, expenses above costs', () => {
  const d = dashStats([
    { costsTotal: 40000, paid: true },              // قديمة مسدَّدة
    { costsTotal: 10000, paid: false },             // قديمة غير مسدَّدة
    { costsTotal: 5000, paidAmt: 2000 },
  ], 70000);
  assert.equal(d.billed, 55000);
  assert.equal(d.paid, 42000);
  assert.equal(d.remaining, 13000);
  assert.equal(d.unpaidCount, 2);
  assert.equal(d.profit, -15000);     // لا ينهار مع ربح سالب
  assert.deepEqual({ ...dashStats([], 0) }, { billed: 0, paid: 0, remaining: 0, unpaidCount: 0, profit: 0 });
});

// ---- v2.4.5: صفحة «اللوحة» (التقارير): المداخيل = التكاليف المفوترة، والصافي = المداخيل − المصاريف ----
const bill = { date: '2026-11-05', grams: '600', goldTotal: 2040000, costsTotal: 179500, net: 1860500 };

test('report: income is billed costs, net is income minus mill expenses', () => {
  const r = reportStats([bill], 30000);
  assert.equal(r.sales, undefined);   // v2.6.0: مجموع ذهب الزبون لا يخرج من التقرير
  assert.equal(r.avgPrice, 3400);     // متوسط سعر الغرام فقط = 2040000 / 600
  assert.equal(r.income, 179500);     // المداخيل
  assert.equal(r.expenses, 30000);
  assert.equal(r.net, 149500);        // 179500 - 30000
  assert.equal(reportStats([bill], 0).net, 179500);
});

test('report: expenses above costs give a negative net, empty list is zero', () => {
  assert.equal(reportStats([bill], 200000).net, -20500);
  assert.deepEqual({ ...reportStats([], 0) }, { income: 0, expenses: 0, net: 0, avgPrice: 0 });
});

test('report series: net per day = costs - expenses of that day', () => {
  const ser = repSeries(
    [bill, { date: '2026-11-05', goldTotal: 100, costsTotal: 500 }],
    [{ date: '2026-11-05', amount: '1000' }, { date: '2026-11-07', amount: '2500' }, { date: '2026-12-01', amount: '9999' }],
    true, '2026-11-01', '2026-11-30');
  assert.deepEqual({ ...ser['11-05'] }, { net: 179500 + 500 - 1000, cost: 180000, exp: 1000 });
  assert.deepEqual({ ...ser['11-07'] }, { net: -2500, cost: 0, exp: 2500 });   // يوم فيه مصاريف فقط
  assert.equal(ser['12-01'], undefined);                                       // خارج الفترة
});

test('report series by month', () => {
  const ser = repSeries([bill], [{ date: '2026-11-20', amount: 4500 }], false, '0000', '9999');
  assert.equal(ser['2026-11'].net, 175000);
});

// ---- v2.4.6: حفظ الإعدادات (الاسم والهاتف وبقية الحقول والبنود) ----
test('settings: name and phones are saved trimmed, startNo is numeric', () => {
  const { n, err } = buildSettings({ name: 'Old', ph1: '111', ph2: '', startNo: 1, currency: 'MRU' },
    { name: '  إدارة دار الذهب ', ph1: ' 38449999 ', ph2: '', startNo: '٥' }, ['A'], []);
  assert.equal(err, null);
  assert.equal(n.name, 'إدارة دار الذهب');
  assert.equal(n.ph1, '38449999');
  assert.equal(n.startNo, 5);          // رقم عربي
  assert.equal(n.currency, 'MRU');     // ما لم يُمسّ يبقى
});

test('settings: empty name is rejected, blank list rows are dropped', () => {
  assert.equal(buildSettings({ name: 'X' }, { name: '   ' }, [], []).err, 'name');
  const { n } = buildSettings({ name: 'X' }, {}, ['الطحن', '  ', ''], [{ name: 'العمال', pct: ' 40 ' }, { name: ' ', pct: '10' }]);
  // نحوّل إلى JSON لأن الكائنات تأتي من صندوق vm (عالم مختلف)
  assert.deepEqual(JSON.parse(JSON.stringify(n.costList)), ['الطحن']);
  assert.deepEqual(JSON.parse(JSON.stringify(n.partList)), [{ name: 'العمال', pct: '40' }]);
  assert.equal(n.name, 'X');
});

// ---- v2.6.4: صيغ المعدودات (دالة واحدة لكل التطبيق) ----
test('arabic plural: 1 singular, 2 dual, 3-10 plural, 11+ singular accusative', () => {
  assert.equal(plural(1, 'inv', 'ar'), 'فاتورة واحدة');
  assert.equal(plural(2, 'inv', 'ar'), 'فاتورتان');
  assert.equal(plural(3, 'inv', 'ar'), '3 فواتير');
  assert.equal(plural(10, 'inv', 'ar'), '10 فواتير');
  assert.equal(plural(11, 'inv', 'ar'), '11 فاتورة');
  assert.equal(plural(250, 'inv', 'ar'), '250 فاتورة');
  assert.equal(plural(0, 'inv', 'ar'), '0 فاتورة');
  assert.equal(plural(1250, 'inv', 'ar'), '1,250 فاتورة');           // فاصل الآلاف كبقية التطبيق
});

test('arabic plural for every noun: customer, gram, message, day, days left, expense, item, partner', () => {
  const want = { cust: ['زبون واحد', 'زبونان', '5 زبائن', '12 زبونًا'], gram: ['غرام واحد', 'غرامان', '4 غرامات', '15 غرامًا'],
    msg: ['رسالة واحدة', 'رسالتان', '7 رسائل', '30 رسالة'], day: ['يوم واحد', 'يومان', '9 أيام', '45 يومًا'],
    dayLeft: ['يوم واحد متبقٍ', 'يومان متبقيان', '6 أيام متبقية', '20 يومًا متبقيًا'], exp: ['مصروف واحد', 'مصروفان', '8 مصروفات', '11 مصروفًا'],
    item: ['بند واحد', 'بندان', '3 بنود', '14 بندًا'], partner: ['شريك واحد', 'شريكان', '10 شركاء', '100 شريكًا'] };
  for (const [k, [a, b, c, d]] of Object.entries(want)) {
    const n = [1, 2, +c.match(/\d+/)[0], +d.match(/\d+/)[0]];
    assert.deepEqual(n.map(x => plural(x, k, 'ar')), [a, b, c, d], k);
  }
});

test('french plural: below 2 singular, otherwise plural', () => {
  assert.equal(plural(0, 'inv', 'fr'), '0 facture');
  assert.equal(plural(1, 'inv', 'fr'), '1 facture');
  assert.equal(plural(2, 'inv', 'fr'), '2 factures');
  assert.equal(plural(25, 'cust', 'fr'), '25 clients');
  assert.equal(plural(1, 'dayLeft', 'fr'), '1 jour restant');
  assert.equal(plural(5, 'dayLeft', 'fr'), '5 jours restants');
  assert.equal(plural(1.5, 'gram', 'fr'), '1.5 gramme');
});

test('plural: fractions and negatives use the default form, unknown nouns fall back to the number', () => {
  assert.equal(plural(12.5, 'gram', 'ar'), '12.5 غرامًا');
  assert.equal(plural(1.5, 'gram', 'ar'), '1.5 غرامًا');        // ليس 1 ولا 2 تمامًا
  assert.equal(plural(-2, 'inv', 'ar'), 'فاتورتان');
  assert.equal(plural(3, 'nothing', 'ar'), '3');
  assert.equal(plural('3', 'inv', 'ar'), '3 فواتير');
  assert.equal(plural(undefined, 'inv', 'ar'), '0 فاتورة');
});

test('every noun has 4 arabic forms and 2 french forms', () => {
  for (const [k, v] of Object.entries(plain(NOUN))) { assert.equal(v.ar.length, 4, k + ' ar'); assert.equal(v.fr.length, 2, k + ' fr'); assert.ok(v.ar.every(Boolean) && v.fr.every(Boolean), k); }
});
