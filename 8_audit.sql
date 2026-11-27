-- 8) المرحلة هـ: سجل التعديلات (admin_audit) — للإضافة فقط.
-- يسجّل تلقائيًا كل إجراء حساس يقوم به مشرف: استلام الرسائل وحسمها، طلبات استعادة كلمة السر،
-- تعيين كلمة سر، تعليق/تفعيل حساب، تعديل الاشتراك، الدفعات، توليد رموز الاعتماد وإلغاؤها.
-- كيف يعرف «من» فعل؟ دالة _admin (قديمة) تضع هوية المشرف في إعداد مؤقت يدوم لطلب واحد فقط
-- (set_config(..., true))، والمشغّلات تقرؤه. ما لا يمرّ بـ _admin (دخول، تسجيل، طلبات المطاحن) لا يُسجَّل.
-- لا كلمة سر ولا بصمة ولا رمز تحقق ولا رمز اعتماد كامل في السجل.
begin;

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
commit;

-- ===================== التراجع (عند الحاجة فقط) =====================
-- ملاحظة: السجل للإضافة فقط؛ حذفه كاملًا يتطلب إزالة مشغّل المنع أولًا (الخطوة الأولى أدناه).
-- begin;
-- drop trigger if exists audit_accounts on public.accounts;
-- drop trigger if exists audit_codes on public.approval_codes;
-- drop trigger if exists audit_payments on public.payments;
-- drop trigger if exists audit_messages on public.messages;
-- drop trigger if exists audit_resets on public.reset_requests;
-- drop function if exists public.admin_audit_list(text, bigint, int, uuid, text, date, date, boolean);
-- drop function if exists public._audit_accounts(), public._audit_codes(), public._audit_payments(), public._audit_messages(), public._audit_resets();
-- drop function if exists public._audit(text, uuid, jsonb);
-- drop trigger if exists admin_audit_no_change on public.admin_audit;
-- drop trigger if exists admin_audit_no_truncate on public.admin_audit;
-- drop table if exists public.admin_audit;
-- drop function if exists public._audit_readonly();
-- -- _admin كما كانت قبل 8:
-- create or replace function public._admin(p_token text)
--  returns public.accounts language plpgsql security definer set search_path to '' as $function$
-- declare a public.accounts;
-- begin
--   a := public._acct(p_token);
--   if a.role<>'admin' or not exists(select 1 from public.admin_phones where phone=a.phone) then raise exception 'E_FORBIDDEN'; end if;
--   return a;
-- end $function$;
-- commit;
