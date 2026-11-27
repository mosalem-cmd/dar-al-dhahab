-- اختبار رجوع للمرحلة هـ (8): كل شيء داخل معاملة تُلغى بخطأ مقصود، ولا يبقى أثر (ولا سطر في السجل).
-- يُشغَّل بعد موافقة المالك فقط. الحسابات المؤقتة وهمية (99900000011..19).
do $t$
declare mig text := $m$

-- 1) الجدول
create table public.admin_audit (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  admin_id    uuid,          -- بلا مفتاح خارجي: يبقى السطر حتى لو حُذف الحساب
  admin_name  text,
  action      text not null,
  target_id   uuid,
  target_name text,
  details     jsonb not null default '{}'::jsonb
);
create index on public.admin_audit (at desc);
create index on public.admin_audit (admin_id, id desc);
create index on public.admin_audit (action, id desc);
alter table public.admin_audit enable row level security;      -- بلا سياسات
revoke all on public.admin_audit from public, anon, authenticated;

-- 2) للإضافة فقط: أي تعديل أو حذف أو تفريغ يُرفض، لأي دور
create or replace function public._audit_readonly()
 returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  raise exception 'E_AUDIT_READONLY';
end $function$;
revoke all on function public._audit_readonly() from public, anon, authenticated;
create trigger admin_audit_no_change before update or delete on public.admin_audit
  for each row execute function public._audit_readonly();
create trigger admin_audit_no_truncate before truncate on public.admin_audit
  for each statement execute function public._audit_readonly();

-- 3) [تعديل دالة قديمة] _admin: كما كانت + تضع هوية المشرف لهذا الطلب فقط
create or replace function public._admin(p_token text)
 returns public.accounts language plpgsql security definer set search_path to '' as $function$
declare a public.accounts;
begin
  a := public._acct(p_token);
  if a.role<>'admin' or not exists(select 1 from public.admin_phones where phone=a.phone) then raise exception 'E_FORBIDDEN'; end if;
  perform set_config('dar.admin_id', a.id::text, true);
  perform set_config('dar.admin_name', coalesce(a.mill_name, ''), true);
  return a;
end $function$;

-- 4) كتابة سطر (لا يكتب شيئًا إن لم يكن الطلب من مشرف)
create or replace function public._audit(p_action text, p_target uuid, p_details jsonb)
 returns void language plpgsql security definer set search_path to '' as $function$
declare aid text := current_setting('dar.admin_id', true); tn text;
begin
  if coalesce(aid, '') = '' then return; end if;
  if p_target is not null then select mill_name into tn from public.accounts where id = p_target; end if;
  insert into public.admin_audit(admin_id, admin_name, action, target_id, target_name, details)
  values (aid::uuid, nullif(current_setting('dar.admin_name', true), ''), p_action, p_target, tn, coalesce(p_details, '{}'::jsonb));
end $function$;
revoke all on function public._audit(text, uuid, jsonb) from public, anon, authenticated;

-- 5) المشغّلات
create or replace function public._audit_accounts()
 returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if coalesce(current_setting('dar.admin_id', true), '') = '' then return null; end if;
  if new.status is distinct from old.status then
    perform public._audit('account_status', new.id, jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  if (new.paid_until, new.setup_fee, new.monthly_fee) is distinct from (old.paid_until, old.setup_fee, old.monthly_fee) then
    perform public._audit('subscription', new.id, jsonb_build_object(
      'paid_until', jsonb_build_array(old.paid_until, new.paid_until),
      'setup_fee', jsonb_build_array(old.setup_fee, new.setup_fee),
      'monthly_fee', jsonb_build_array(old.monthly_fee, new.monthly_fee)));
  end if;
  if new.pass_hash is distinct from old.pass_hash then
    perform public._audit('password_set', new.id, '{}'::jsonb);          -- بلا أي بصمة
  end if;
  return null;
end $function$;

create or replace function public._audit_codes()
 returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if coalesce(current_setting('dar.admin_id', true), '') = '' then return null; end if;
  if tg_op = 'INSERT' then
    perform public._audit('code_create', null, jsonb_build_object('code', '…' || right(new.code, 3), 'note', new.note, 'expires_at', new.expires_at, 'for_admin', new.for_admin));
  elsif new.revoked and not coalesce(old.revoked, false) then
    perform public._audit('code_revoke', null, jsonb_build_object('code', '…' || right(new.code, 3), 'note', new.note));
  end if;
  return null;
end $function$;

create or replace function public._audit_payments()
 returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if coalesce(current_setting('dar.admin_id', true), '') = '' then return null; end if;
  if tg_op = 'INSERT' then
    perform public._audit('payment_add', new.account_id, jsonb_build_object('payment_id', new.id, 'amount', new.amount, 'currency', new.currency, 'kind', new.kind, 'status', new.status));
  elsif new.status is distinct from old.status then
    perform public._audit('payment_status', new.account_id, jsonb_build_object('payment_id', new.id, 'amount', new.amount, 'from', old.status, 'to', new.status));
  end if;
  return null;
end $function$;

create or replace function public._audit_messages()
 returns trigger language plpgsql security definer set search_path to '' as $function$
declare d jsonb := jsonb_build_object('message_id', new.id, 'kind', new.kind);
begin
  if coalesce(current_setting('dar.admin_id', true), '') = '' then return null; end if;
  if new.claimed_by is not null and new.claimed_by is distinct from old.claimed_by then
    perform public._audit('msg_claim', new.account_id, d);
  elsif new.claimed_by is null and old.claimed_by is not null and new.status = old.status then
    perform public._audit('msg_release', new.account_id, d);
  end if;
  if new.status is distinct from old.status or (new.reply is distinct from old.reply and new.status = old.status) then
    perform public._audit('msg_' || new.status, new.account_id, d);
  end if;
  return null;
end $function$;

create or replace function public._audit_resets()
 returns trigger language plpgsql security definer set search_path to '' as $function$
declare d jsonb := jsonb_build_object('request_id', new.id);
begin
  if coalesce(current_setting('dar.admin_id', true), '') = '' then return null; end if;
  if old.status = 'new' and new.status = 'processing' then
    perform public._audit('reset_claim', new.account_id, d);
  elsif new.status = 'done' and old.status <> 'done' then
    perform public._audit('reset_approve', new.account_id, d);
  elsif new.status = 'rejected' and old.status <> 'rejected' then
    perform public._audit('reset_reject', new.account_id, d || jsonb_build_object('reason', case when new.attempts >= 3 then 'wrong_code' else 'admin' end));
  elsif new.attempts > old.attempts then
    perform public._audit('reset_wrong_code', new.account_id, d || jsonb_build_object('attempts', new.attempts));
  end if;
  return null;
end $function$;

revoke all on function public._audit_accounts() from public, anon, authenticated;
revoke all on function public._audit_codes()    from public, anon, authenticated;
revoke all on function public._audit_payments() from public, anon, authenticated;
revoke all on function public._audit_messages() from public, anon, authenticated;
revoke all on function public._audit_resets()   from public, anon, authenticated;

create trigger audit_accounts after update on public.accounts for each row execute function public._audit_accounts();
create trigger audit_codes after insert or update on public.approval_codes for each row execute function public._audit_codes();
create trigger audit_payments after insert or update on public.payments for each row execute function public._audit_payments();
create trigger audit_messages after update on public.messages for each row execute function public._audit_messages();
create trigger audit_resets after update on public.reset_requests for each row execute function public._audit_resets();

-- 6) القراءة: للمشرفين فقط، صفحات (الأحدث أولًا أو الأقدم أولًا)، وتصفية بالمشرف ونوع الإجراء والتاريخ
create or replace function public.admin_audit_list(p_token text, p_cursor bigint default null, p_limit int default 50,
    p_admin uuid default null, p_action text default null, p_from date default null, p_to date default null, p_oldest_first boolean default false)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token); lim int := least(greatest(coalesce(p_limit, 50), 1), 200); rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(x) order by case when p_oldest_first then x.id end asc, case when not p_oldest_first then x.id end desc), '[]'::jsonb) into rows
  from (select * from public.admin_audit l
         where (p_cursor is null or (case when p_oldest_first then l.id > p_cursor else l.id < p_cursor end))
           and (p_admin is null or l.admin_id = p_admin)
           and (p_action is null or l.action = p_action)
           and (p_from is null or l.at >= p_from)
           and (p_to is null or l.at < p_to + 1)
         order by case when p_oldest_first then l.id end asc, case when not p_oldest_first then l.id end desc
         limit lim) x;
  return jsonb_build_object('rows', rows,
    'admins', coalesce((select jsonb_agg(jsonb_build_object('id', s.admin_id, 'name', s.name) order by s.name)
                        from (select admin_id, max(admin_name) as name from public.admin_audit group by admin_id) s), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(distinct action) from public.admin_audit), '[]'::jsonb));
end $function$;
revoke all on function public.admin_audit_list(text, bigint, int, uuid, text, date, date, boolean) from public, authenticated;
grant execute on function public.admin_audit_list(text, bigint, int, uuid, text, date, date, boolean) to anon;
$m$;
begin
 execute mig;
 execute $x$
do $u$

declare ma uuid; mb uuid; ad1 uuid; ad2 uuid; t1 text; t2 text; tm text; r jsonb; n int; n0 int; res text := ''; m1 bigint; q bigint; pid bigint; c text; j jsonb; ok boolean;
begin
 n0 := (select count(*) from public.admin_audit);
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000011',extensions.crypt('oldpass1',extensions.gen_salt('bf',4)),'TEST A','mill') returning id into ma;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000012',extensions.crypt('oldpass2',extensions.gen_salt('bf',4)),'TEST B','mill') returning id into mb;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000019',extensions.crypt('adminpass',extensions.gen_salt('bf',4)),'TEST ADMIN 1','admin') returning id into ad1;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000018',extensions.crypt('adminpass',extensions.gen_salt('bf',4)),'TEST ADMIN 2','admin') returning id into ad2;
 insert into public.admin_phones(phone) values ('99900000019'),('99900000018');
 t1 := public._new_session(ad1); t2 := public._new_session(ad2); tm := public._new_session(ma);
 res := res||chr(10)||(case when (select count(*) from public.admin_audit)=n0 then 'PASS ' else 'FAIL ' end||'01 creating accounts/sessions directly is not logged');
 -- أفعال غير المشرف لا تُسجَّل
 perform public.login('99900000011','oldpass1');
 perform public.change_password(tm,'oldpass1','oldpass1b');
 perform public.reset_request('99900000012','newpassb');
 insert into public.messages(account_id,kind,subject,body) values (ma,'complaint','s','b') returning id into m1;
 res := res||chr(10)||(case when (select count(*) from public.admin_audit)=n0 then 'PASS ' else 'FAIL ' end||'02 mill/anonymous actions (login, change password, reset request, message) are NOT logged');
 -- أفعال المشرف
 perform public.admin_set_status(t1,ma,'suspended');
 j := (select to_jsonb(l) from public.admin_audit l where action='account_status' and target_id=ma order by id desc limit 1);
 res := res||chr(10)||(case when j->>'admin_name'='TEST ADMIN 1' and j->>'target_name'='TEST A' and j->'details'->>'to'='suspended' and (j->>'admin_id')::uuid=ad1 then 'PASS ' else 'FAIL ' end||'03 suspend logged with admin, target and old/new status');
 perform public.admin_set_status(t1,ma,'active');
 perform public.admin_set_sub(t2,ma,current_date+30,1000,500);
 res := res||chr(10)||(case when exists(select 1 from public.admin_audit where action='subscription' and target_id=ma and admin_name='TEST ADMIN 2') then 'PASS ' else 'FAIL ' end||'04 subscription change logged under the right admin');
 perform public.admin_reset_password(t1,mb,'resetpass1');
 j := (select to_jsonb(l) from public.admin_audit l where action='password_set' and target_id=mb order by id desc limit 1);
 res := res||chr(10)||(case when j is not null and j->'details'='{}'::jsonb then 'PASS ' else 'FAIL ' end||'05 admin password reset logged without any hash');
 perform public.admin_gen_codes(t1,2,'TEST NOTE',3);
 select count(*) into n from public.admin_audit where action='code_create' and admin_id=ad1;
 ok := n=2;
 for c in select code from public.approval_codes where created_by=ad1 loop
   ok := ok and not exists(select 1 from public.admin_audit where details::text like '%'||c||'%' or details::text like '%'||substr(c,1,8)||'%');
 end loop;
 res := res||chr(10)||(case when ok then 'PASS ' else 'FAIL ' end||'06 two codes logged, neither the full code nor its first half stored');
 c := (select code from public.approval_codes where created_by=ad1 limit 1);
 perform public.admin_revoke_code(t2,c);
 res := res||chr(10)||(case when exists(select 1 from public.admin_audit where action='code_revoke' and admin_id=ad2) then 'PASS ' else 'FAIL ' end||'07 code revoke logged');
 perform public.admin_add_payment(t1,ma,700,'cash','','','test','monthly');
 select id into pid from public.payments where account_id=ma order by id desc limit 1;
 res := res||chr(10)||(case when exists(select 1 from public.admin_audit where action='payment_add' and target_id=ma) then 'PASS ' else 'FAIL ' end||'08 admin-added payment logged');
 insert into public.payments(account_id,amount,currency,method,status,kind) values (mb,300,'MRU','cash','pending','monthly') returning id into pid;
 perform public.admin_set_payment(t2,pid,'rejected');
 res := res||chr(10)||(case when exists(select 1 from public.admin_audit where action='payment_status' and target_id=mb and details->>'to'='rejected') then 'PASS ' else 'FAIL ' end||'09 payment decision logged');
 -- الرسائل
 perform public.admin_msg_claim(t1,m1); perform public.admin_reply(t1,m1,'رد','replied'); perform public.admin_reply(t1,m1,'رد','rejected');
 res := res||chr(10)||(case when exists(select 1 from public.admin_audit where action='msg_claim' and target_id=ma) and exists(select 1 from public.admin_audit where action='msg_replied') and exists(select 1 from public.admin_audit where action='msg_rejected') then 'PASS ' else 'FAIL ' end||'10 message claim, reply and reject logged');
 -- استعادة كلمة السر
 select id into q from public.reset_requests where account_id=mb and status='new' order by id desc limit 1;
 perform public.admin_reset_claim(t1,q); update public.reset_requests set vcode='4444' where id=q;
 perform public.admin_reset_approve(t1,q,'0000'); r := public.admin_reset_approve(t1,q,'4444');
 res := res||chr(10)||(case when exists(select 1 from public.admin_audit where action='reset_claim' and target_id=mb) and exists(select 1 from public.admin_audit where action='reset_wrong_code' and target_id=mb) and exists(select 1 from public.admin_audit where action='reset_approve' and target_id=mb) then 'PASS ' else 'FAIL ' end||'11 reset claim, wrong code and approval logged');
 res := res||chr(10)||(case when not exists(select 1 from public.admin_audit where details::text ~ '4444|\$2[aby]\$|resetpass1|newpassb|adminpass|oldpass') then 'PASS ' else 'FAIL ' end||'12 no password, hash or verification code anywhere in the log');
 -- للإضافة فقط
 begin update public.admin_audit set action='x' where id=(select max(id) from public.admin_audit); res := res||chr(10)||'FAIL 13 update allowed'; exception when others then res := res||chr(10)||(case when sqlerrm='E_AUDIT_READONLY' then 'PASS ' else 'FAIL ' end||'13 update refused'); end;
 begin delete from public.admin_audit where id=(select max(id) from public.admin_audit); res := res||chr(10)||'FAIL 14 delete allowed'; exception when others then res := res||chr(10)||(case when sqlerrm='E_AUDIT_READONLY' then 'PASS ' else 'FAIL ' end||'14 delete refused'); end;
 begin truncate public.admin_audit; res := res||chr(10)||'FAIL 15 truncate allowed'; exception when others then res := res||chr(10)||(case when sqlerrm='E_AUDIT_READONLY' then 'PASS ' else 'FAIL ' end||'15 truncate refused'); end;
 -- القراءة
 tm := public._new_session(ma);   -- جلسة جديدة: تغيير كلمة السر أعلاه أنهى الجلسات السابقة
 begin perform public.admin_audit_list(tm); res := res||chr(10)||'FAIL 16 mill read the log'; exception when others then res := res||chr(10)||(case when sqlerrm='E_FORBIDDEN' then 'PASS ' else 'FAIL ' end||'16 a mill cannot read the log: '||sqlerrm); end;
 r := public.admin_audit_list(t1, null, 3);
 res := res||chr(10)||(case when jsonb_array_length(r->'rows')=3 and (r->'rows'->0->>'id')::bigint > (r->'rows'->1->>'id')::bigint and jsonb_array_length(r->'admins')>=2 then 'PASS ' else 'FAIL ' end||'17 newest first, page size respected, admin list for filtering');
 j := public.admin_audit_list(t1, (r->'rows'->2->>'id')::bigint, 3);
 res := res||chr(10)||(case when (j->'rows'->0->>'id')::bigint < (r->'rows'->2->>'id')::bigint then 'PASS ' else 'FAIL ' end||'18 next page continues after the cursor');
 r := public.admin_audit_list(t1, null, 50, ad2);
 res := res||chr(10)||(case when jsonb_array_length(r->'rows')>0 and not exists(select 1 from jsonb_array_elements(r->'rows') x where (x->>'admin_id')::uuid<>ad2) then 'PASS ' else 'FAIL ' end||'19 filter by admin');
 r := public.admin_audit_list(t1, null, 50, null, 'code_create');
 res := res||chr(10)||(case when jsonb_array_length(r->'rows')>=2 and not exists(select 1 from jsonb_array_elements(r->'rows') x where x->>'action'<>'code_create') then 'PASS ' else 'FAIL ' end||'20 filter by action');
 r := public.admin_audit_list(t1, null, 50, null, null, current_date+1, current_date+2);
 res := res||chr(10)||(case when jsonb_array_length(r->'rows')=0 then 'PASS ' else 'FAIL ' end||'21 date filter (tomorrow) returns nothing');
 r := public.admin_audit_list(t1, null, 2, null, null, null, null, true);
 res := res||chr(10)||(case when (r->'rows'->0->>'id')::bigint < (r->'rows'->1->>'id')::bigint then 'PASS ' else 'FAIL ' end||'22 oldest-first order');
 res := res||chr(10)||(case when (select count(*) from public.admin_audit)>n0 and not exists(select 1 from public.admin_audit where action like 'audit%') then 'PASS ' else 'FAIL ' end||'23 reading the log does not write to it');
 -- الصلاحيات
 res := res||chr(10)||(case when not has_table_privilege('anon','public.admin_audit','select') and not has_table_privilege('authenticated','public.admin_audit','select') and not has_table_privilege('anon','public.admin_audit','insert')
   and has_function_privilege('anon','public.admin_audit_list(text,bigint,integer,uuid,text,date,date,boolean)','execute') and not has_function_privilege('authenticated','public.admin_audit_list(text,bigint,integer,uuid,text,date,date,boolean)','execute')
   and not has_function_privilege('anon','public._audit(text,uuid,jsonb)','execute') then 'PASS ' else 'FAIL ' end||'24 table closed; only the admin read function is callable');
 res := res||chr(10)||(case when (select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc where pronamespace='public'::regnamespace and proname in ('_admin','_audit','_audit_readonly','_audit_accounts','_audit_codes','_audit_payments','_audit_messages','_audit_resets','admin_audit_list')) then 'PASS ' else 'FAIL ' end||'25 all functions security definer with empty search_path');
 begin perform public._admin(tm); res := res||chr(10)||'FAIL 26 _admin accepted a mill'; exception when others then res := res||chr(10)||(case when sqlerrm='E_FORBIDDEN' then 'PASS ' else 'FAIL ' end||'26 _admin still refuses mills: '||sqlerrm); end;
 raise exception E'ROLLBACK_TEST_RESULT\n%', res;
end

$u$
$x$;
end
$t$;
