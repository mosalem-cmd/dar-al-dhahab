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

// v2.6.3: زر الرجوع في الهاتف يمر بنفس منطق زر الرجوع داخل التطبيق (ومنه تنبيه الفاتورة غير المحفوظة)
test('phone back button is bridged to the in-app back logic', () => {
  const html = read('index.html');
  assert.match(html, /window\.addEventListener\('popstate',[\s\S]{0,200}goBack\(\)/, 'popstate must call goBack');
  assert.match(html, /function show\(v,keep(,shell)?\)\{[\s\S]*?syncBackEntry\(\);\n\}/, 'show() keeps the history entry in sync');
  assert.match(html, /const isRootView=v=>v==='home'\|\|v==='wel'/, 'home/login stay the exit point');
  assert.match(read('help.js'), /close: closeChat/, 'help chat can be closed by the back button');
});

// v2.6.4: إصلاح خروج المستخدم من التطبيق عند ضغط/إعادة رسم متتالية (history.back() غير متزامن)
test('phone-back bridge never fires a second history.back() while one is pending', () => {
  const html = read('index.html');
  assert.match(html, /let ignorePop=false,backPending=false;/);
  assert.match(html, /function syncBackEntry\(\)\{\s*if\(backPending\)return;/, 'must skip while a back is pending');
  assert.match(html, /else if\(!need&&has\)\{backPending=true;ignorePop=true;history\.back\(\)\}/);
  assert.match(html, /if\(ignorePop\)\{ignorePop=false;backPending=false;syncBackEntry\(\);return\}/, 'pending cleared and state reconciled on popstate');
});

// v2.6.4: التنقل السريع: هيكل فوري للصفحة الثقيلة، وآخر ضغطة تُنفَّذ، وتخزين نتائج الحسابات الثقيلة
test('fast navigation: shell first, last tap wins, heavy results cached', () => {
  const html = read('index.html');
  assert.match(html, /function navTo\(v\)\{[\s\S]*sec\.innerHTML=SKEL;[\s\S]*show\(key,false,true\);/, 'shell shown immediately');
  assert.match(html, /requestAnimationFrame\(\(\)=>setTimeout\(\(\)=>\{if\(my!==navTok\|\|sec\.dataset\.ready==='1'\)return;navRun\(v\)\}/, 'stale render cancelled by the navigation token');
  assert.match(html, /function goRaw\(v\)\{closeMenu\(\);\s*navTok\+\+;/, 'every navigation bumps the token');
  assert.match(html, /if\(!shell\)navTok\+\+;/, 'direct renders cancel pending ones');
  assert.match(html, /key==='form'\)\$\('#bar'\)\.classList\.add\('hide'\)/, 'save bar hidden while the invoice form is a skeleton');
  assert.match(html, /function clients\(\)\{if\(_clK&&_clI===invoices&&_clC===customers\)return _clK/, 'clients() memoised on its sources');
  assert.match(html, /if\(RC&&RC\.k===rk&&RC\.i===invoices&&RC\.e===expenses\)/, 'dashboard page cached until data/period/language change');
  assert.match(html, /\.card\.inv\{content-visibility:auto/, 'long lists skip off-screen rendering');
  assert.match(html, /prefers-reduced-motion:reduce\)\{\.sk\{animation:none\}/, 'skeleton respects reduced motion');
});

// v2.6.4: كل رقم يتبعه معدود يمر بدالة الصيغ الواحدة (لا نص رقم + كلمة ثابتة)
test('counted nouns go through the single plural helper', () => {
  const html = read('index.html');
  for (const stale of ["${c.count} ${t('invCount')}", "${a.invoices} ${t('invCount')}", "s.d+' '+t('daysLeft')", "'+unp.length+')'", "${tI('kUnpaid')} (${c.unpaid})", "${tI('more')} (${list.length-shown})"])
    assert.ok(!html.includes(stale), 'hard-coded count+noun: ' + stale);
  for (const used of ["cnt(c.count,'inv')", "cnt(a.invoices,'inv')", "cnt(s.d,'dayLeft')", "cnt(unp.length,'inv')", "cnt(c.unpaid,'inv')", "cnt(list.length-shown,'inv')"])
    assert.ok(html.includes(used), 'missing plural call: ' + used);
});

// v2.6.4: الإعدادات والملف الشخصي: حفظ يدوي فقط
test('settings are saved manually only (no auto-save), with save/cancel bar and leave guard', () => {
  const html = read('index.html');
  const calls = [...html.matchAll(/await persistSettings\(\)/g)].length;   // الاستدعاءات فقط (دون التعريف)
  assert.equal(calls, 1, 'persistSettings() may be called only from saveSetGuard');
  assert.match(html, /async function saveSetGuard\(\)\{[\s\S]*await persistSettings\(\)/);
  assert.doesNotMatch(html, /setDeb|setTimeout\(async\(\)=>\{const err=await persistSettings/, 'debounced auto-save removed');
  assert.match(html, /<button id="saveSet" class="pri" disabled>/, 'save button starts disabled');
  assert.match(html, /<button id="cancelSet" disabled>/, 'cancel button starts disabled');
  assert.match(html, /<div class="setbar" id="setBar" hidden>/, 'bar hidden until there is a change');
  assert.match(html, /\$\('#setBar'\)\.hidden=!d&&!\$\('#setStat'\)\.textContent/, 'bar follows the dirty state / saved message');
  assert.match(html, /b\.disabled=!d;c\.disabled=!d;/, 'both buttons follow the dirty state');
  assert.match(html, /markDirty\('set',saveSetGuard,'setStat'\)/, 'leaving with changes triggers the guard');
  assert.match(html, /function cancelSet\(\)\{setDraft=null;clearDirty\(\);openSet\(\)\}/, 'cancel restores the saved values');
  assert.match(html, /unsavedQ:'لديك تغييرات غير محفوظة، هل تريد حفظها؟'/);
  assert.match(html, /function openSet\(keep\)\{\s*if\(!keep\)\{setCosts=\[\.\.\.defCosts\(\)\];setParts=defParts\(\)\.map\(p=>\(\{\.\.\.p\}\)\);setDraft=null\}/, 'a fresh open clears the draft BEFORE rendering');
  assert.match(html, /captureDraft\(\);lang=b\.dataset\.v;[\s\S]*captureDraft\(\);theme=b\.dataset\.v;/, 'language and theme stay instant and keep the typed draft');
  assert.match(html, /onSave:v=>\{if\(!v\.name\)return t\('nameReq'\);[\s\S]*refreshSetLists\(\);updateSetBar\(\)\}/, 'item sheets only change the working copy');
});

// v2.7.0 (المرحلة أ): استعادة كلمة السر: طلب فقط، الرابط مخفي حتى تكتمل صفحة المشرف
test('forgot password: request form wired to reset_request (phase A)', () => {
  const html = read('index.html');
  assert.match(html, /let RESET_ENABLED=true;/, 'enabled now that the admin side exists');
  assert.match(html, /!R&&RESET_ENABLED\?`<a href="#" id="aForgot"/, 'link only on the login tab and only when enabled');
  assert.match(html, /rpc\('reset_request',\{p_phone:\$\('#fPhone'\)\.value,p_new:pw\}\)/);
  assert.match(html, /if\(pw!==\$\('#fPass2'\)\.value\)/, 'confirmation required');
  assert.match(html, /E_NO_ACCOUNT:'يرجى إدخال رقم الحساب بشكل صحيح'/);
  const sql = read('7a_reset_request.sql');
  assert.match(sql, /extensions\.crypt\(p_new, extensions\.gen_salt\('bf', 10\)\)/, 'only a bcrypt hash is stored');
  assert.match(sql, /security definer set search_path to ''/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, />= 3 then[\s\S]{0,40}E_RATE/, '3 requests per hour per account');
  assert.doesNotMatch(sql, /update public\.accounts/, 'a request never changes an account');
  const lines = html.split('\n').filter(x => /^\s*phone:'/.test(x));          // سطرا النصوص: عربي ثم فرنسي
  assert.equal(lines.length, 2);
  for (const [i, l] of ['ar', 'fr'].entries()) for (const k of ['forgotL', 'forgotTitle', 'forgotAcct', 'forgotNew', 'forgotSend', 'forgotOk', 'forgotBack', 'E_NO_ACCOUNT', 'E_BUSY', 'E_RATE', 'E_WEAK_PASS'])
    assert.ok(lines[i].includes(k + ":'"), l + ': missing string ' + k);
  assert.match(sql, /revoke all on function public\.reset_request\(text, text\) from public, authenticated;\s*grant execute on function public\.reset_request\(text, text\) to anon;/);
});

// v2.8.0: استعادة كلمة السر: صفحة المشرف (استلام، معلومات، موافقة برمز التحقق، رفض) وSQL المرحلة ب
test('forgot password (admin side): claim, info, approve with verification code, reject', () => {
  const html = read('index.html'), sql = read('7b_reset_admin.sql');
  assert.match(html, /\['rst','aReset','shield'\]/, 'admin tab');
  for (const fn of ['admin_reset_list', 'admin_reset_claim', 'admin_reset_info', 'admin_reset_approve', 'admin_reset_reject']) {
    assert.match(html, new RegExp(`rpc\\('${fn}'`), 'UI calls ' + fn);
    assert.match(sql, new RegExp(`function public\\.${fn}\\(`), 'SQL defines ' + fn);
  }
  assert.match(html, /p_vcode:v/, 'approval sends the verification code the owner read out');
  assert.match(html, /\^\\d\{4\}\$/, 'code format checked on the client');
  assert.match(html, /x&&x\.code/, 'the owner sees the verification code after sending');
  assert.match(sql, /update public\.reset_requests set status = 'processing'[\s\S]*where id = p_id and status = 'new'[\s\S]*returning \* into r/, 'claim is one atomic UPDATE ... WHERE status=new RETURNING');
  const fnBody = n => { const st = sql.indexOf(`function public.${n}(`); return sql.slice(st, sql.indexOf('end $function$', st)); };
  for (const n of ['admin_reset_info', 'admin_reset_approve', 'admin_reset_reject'])
    assert.match(fnBody(n), /claimed_by = ad\.id/, n + ': only the claimant');
  assert.match(html, /info\.err/, 'a failed info fetch becomes an error state, not a reload loop');
  assert.doesNotMatch(html, /catch\(e=>done\(errT\(e\)\)\)\}\)/, 'no reload from the info fetch error path');
  assert.match(sql, /update public\.accounts set pass_hash = r\.new_hash/, 'activates the owner\'s own stored hash, never a client value');
  assert.match(sql, /delete from public\.sessions where account_id = r\.account_id/, 'old sessions closed');
  assert.match(sql, /return jsonb_build_object\('error', 'E_VCODE'\)/, 'wrong code returned as a value so the attempt counter persists');
  assert.doesNotMatch(sql, /'net'|'grams'/, 'admin info never exposes customer gold or net');
  assert.doesNotMatch(sql, /grant [^;]* to (authenticated|public)/i);
  const rt = read('sql_tests/7b_rollback_test.sql');
  assert.match(rt, /ROLLBACK_TEST_RESULT/, 'rollback test always ends with an intentional error');
  for (const l of [html.split('\n').find(x => /^\s*phone:'الهاتف'/.test(x)), html.split('\n').find(x => /^\s*phone:'Tél'/.test(x))])
    for (const k of ['aReset', 'rstWarn', 'rstClaim', 'rstApprove', 'rstReject', 'rstVcode', 'rstDone', 'E_VCODE', 'E_NOT_CLAIMED', 'rstCodeShow', 'forgotCodeNote'])
      assert.ok(l.includes(k + ":'"), 'missing string ' + k);
});
