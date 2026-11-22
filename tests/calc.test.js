// Tests for the invoice math in index.html (node:test, no dependencies).
const test = require('node:test');
const assert = require('node:assert/strict');
const { calc, num, fmt, dashStats, reportStats, repSeries } = require('./extract');

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
const bill = { date: '2026-11-05', goldTotal: 2040000, costsTotal: 179500, net: 1860500 };

test('report: income is billed costs, net is income minus mill expenses', () => {
  const r = reportStats([bill], 30000);
  assert.equal(r.sales, 2040000);     // مبيعات الذهب (بطاقة منفصلة)
  assert.equal(r.income, 179500);     // المداخيل
  assert.equal(r.expenses, 30000);
  assert.equal(r.net, 149500);        // 179500 - 30000
  assert.equal(reportStats([bill], 0).net, 179500);
});

test('report: expenses above costs give a negative net, empty list is zero', () => {
  assert.equal(reportStats([bill], 200000).net, -20500);
  assert.deepEqual({ ...reportStats([], 0) }, { sales: 0, income: 0, expenses: 0, net: 0 });
});

test('report series: net per day = costs - expenses of that day', () => {
  const ser = repSeries(
    [bill, { date: '2026-11-05', goldTotal: 100, costsTotal: 500 }],
    [{ date: '2026-11-05', amount: '1000' }, { date: '2026-11-07', amount: '2500' }, { date: '2026-12-01', amount: '9999' }],
    true, '2026-11-01', '2026-11-30');
  assert.deepEqual({ ...ser['11-05'] }, { net: 179500 + 500 - 1000, sales: 2040100, cost: 180000 });
  assert.deepEqual({ ...ser['11-07'] }, { net: -2500, sales: 0, cost: 0 });   // يوم فيه مصاريف فقط
  assert.equal(ser['12-01'], undefined);                                       // خارج الفترة
});

test('report series by month', () => {
  const ser = repSeries([bill], [{ date: '2026-11-20', amount: 4500 }], false, '0000', '9999');
  assert.equal(ser['2026-11'].net, 175000);
});
