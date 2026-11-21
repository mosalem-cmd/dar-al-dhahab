// Tests for the invoice math in index.html (node:test, no dependencies).
const test = require('node:test');
const assert = require('node:assert/strict');
const { calc, num, fmt } = require('./extract');

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
