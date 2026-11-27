-- 7ب+ج) استعادة كلمة السر: جهة المشرف (استلام، معلومات، موافقة تفعّل كلمة سر المالك، رفض) + إغلاق ثغرة استبدال الطلب.
-- يُضاف رمز تحقق من 4 أرقام يظهر على جهاز صاحب الطلب ويقرؤه للمشرف؛ الموافقة لا تنجح إلا به (يربط الطلب بالشخص الذي اتصل به المشرف).
-- لا يُعدَّل أي دالة قديمة؛ الدالة الوحيدة المعدّلة reset_request أُنشئت في 7أ ولم تُستعمل بعد.
begin;

alter table public.reset_requests
  add column vcode      text,                 -- رمز التحقق (4 أرقام) يظهر على جهاز صاحب الطلب
  add column handled_at timestamptz,
  add column attempts   int not null default 0;  -- محاولات رمز تحقق خاطئة من المشرف

-- تنظيف: ينتهي المعلّق بعد 24 ساعة، ويُفرج عن استلام مضى عليه 15 دقيقة، ويُحذف ما مضى عليه 90 يومًا
create or replace function public._reset_housekeeping()
 returns void language plpgsql security definer set search_path to '' as $function$
begin
  update public.reset_requests set status = 'expired', new_hash = null, vcode = null
   where status in ('new','processing') and expires_at < now();
  update public.reset_requests set status = 'new', claimed_by = null, claimed_at = null
   where status = 'processing' and claimed_at < now() - interval '15 minutes';
  delete from public.reset_requests where created_at < now() - interval '90 days';
end $function$;
revoke all on function public._reset_housekeeping() from public, anon, authenticated;

-- الطلب (مجهول). التعديلات عن 7أ: قفل لكل رقم ضد التزامن، لا يُلغى طلب سابق (المشرف يطابق الرمز)، ويُرجع رمز التحقق.
create or replace function public.reset_request(p_phone text, p_new text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ph text := public._digits(p_phone); a public.accounts; vc text; b bytea;
begin
  if length(coalesce(p_new,'')) < 6 then raise exception 'E_WEAK_PASS'; end if;
  perform public._reset_housekeeping();
  if (select count(*) from public.reset_requests where created_at > now() - interval '1 hour') >= 30 then raise exception 'E_RATE'; end if;
  select * into a from public.accounts where phone = ph and role = 'mill';
  if a.id is null then raise exception 'E_NO_ACCOUNT'; end if;
  perform pg_advisory_xact_lock(hashtext('reset:' || a.id::text));
  if (select count(*) from public.reset_requests where account_id = a.id and created_at > now() - interval '1 hour') >= 3 then raise exception 'E_RATE'; end if;
  b := extensions.gen_random_bytes(2); vc := lpad(((get_byte(b,0)*256 + get_byte(b,1)) % 10000)::text, 4, '0');   -- رمز تحقق من 4 أرقام
  insert into public.reset_requests(account_id, new_hash, vcode)
   values (a.id, extensions.crypt(p_new, extensions.gen_salt('bf', 10)), vc);
  return jsonb_build_object('ok', true, 'code', vc);
end $function$;

-- قائمة الطلبات للمشرف: جديدة أو قيد المعالجة
create or replace function public.admin_reset_list(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  perform public._reset_housekeeping();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'account_id', a.id, 'name', a.mill_name, 'phone', a.phone, 'status', r.status,
      'created_at', r.created_at, 'expires_at', r.expires_at,
      'claimed_by', c.mill_name, 'claimed_at', r.claimed_at, 'mine', r.claimed_by = ad.id,
      'n24', (select count(*) from public.reset_requests x where x.account_id = r.account_id and x.created_at > now() - interval '24 hours'))
      order by r.created_at desc)
    from public.reset_requests r
    join public.accounts a on a.id = r.account_id
    left join public.accounts c on c.id = r.claimed_by
    where r.status in ('new','processing')), '[]'::jsonb);
end $function$;

-- استلام ذرّي: يفوز مشرف واحد فقط؛ الآخر يعرف من استلم
create or replace function public.admin_reset_claim(p_token text, p_id bigint)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token); r public.reset_requests; who text;
begin
  perform public._reset_housekeeping();
  update public.reset_requests set status = 'processing', claimed_by = ad.id, claimed_at = now()
   where id = p_id and status = 'new' and expires_at > now() returning * into r;
  if r.id is null then
    select c.mill_name into who from public.reset_requests x left join public.accounts c on c.id = x.claimed_by where x.id = p_id and x.status = 'processing';
    return jsonb_build_object('claimed', false, 'by', who);
  end if;
  return jsonb_build_object('claimed', true);
end $function$;

-- معلومات أساسية عن الحساب للمشرف (بلا ذهب الزبائن ولا صافيه): من استلم الطلب فقط
create or replace function public.admin_reset_info(p_token text, p_id bigint)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token); r public.reset_requests; a public.accounts; s public.acct_stats;
begin
  select * into r from public.reset_requests where id = p_id and status = 'processing' and claimed_by = ad.id;
  if r.id is null then raise exception 'E_NOT_CLAIMED'; end if;
  select * into a from public.accounts where id = r.account_id;
  select * into s from public.acct_stats where account_id = a.id;
  return jsonb_build_object('name', a.mill_name, 'phone', a.phone, 'phone2', a.phone2, 'created_at', a.created_at,
    'last_login', a.last_login, 'paid_until', a.paid_until, 'status', a.status,
    'invoices', coalesce(s.invoices, 0), 'customers', coalesce(s.customers, 0));
end $function$;

-- موافقة: لمن استلم فقط، ورمز التحقق يطابق، وتفعّل كلمة السر المخزّنة (بصمة صاحب الطلب نفسه)
create or replace function public.admin_reset_approve(p_token text, p_id bigint, p_vcode text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token); r public.reset_requests;
begin
  perform public._reset_housekeeping();
  select * into r from public.reset_requests where id = p_id and status = 'processing' and claimed_by = ad.id for update;
  if r.id is null then raise exception 'E_NOT_CLAIMED'; end if;
  if r.vcode is distinct from trim(coalesce(p_vcode,'')) then
    update public.reset_requests
       set attempts = attempts + 1,
           status = case when attempts + 1 >= 3 then 'rejected' else status end,
           new_hash = case when attempts + 1 >= 3 then null else new_hash end,
           handled_at = case when attempts + 1 >= 3 then now() else handled_at end
     where id = r.id;
    return jsonb_build_object('error', 'E_VCODE');      -- تُرجَع كقيمة ليُحفظ عدّاد المحاولات
  end if;
  update public.accounts set pass_hash = r.new_hash, failed_count = 0, locked_until = null where id = r.account_id and role = 'mill';
  delete from public.sessions where account_id = r.account_id;
  update public.reset_requests set status = 'done', new_hash = null, vcode = null, handled_at = now() where id = r.id;
  update public.reset_requests set status = 'expired', new_hash = null, vcode = null
   where account_id = r.account_id and status in ('new','processing') and id <> r.id;
  return jsonb_build_object('ok', true);
end $function$;

-- رفض: لمن استلم فقط
create or replace function public.admin_reset_reject(p_token text, p_id bigint)
 returns void language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  update public.reset_requests set status = 'rejected', new_hash = null, vcode = null, handled_at = now()
   where id = p_id and status = 'processing' and claimed_by = ad.id;
  if not found then raise exception 'E_NOT_CLAIMED'; end if;
end $function$;

revoke all on function public.admin_reset_list(text)               from public, authenticated;
revoke all on function public.admin_reset_claim(text, bigint)      from public, authenticated;
revoke all on function public.admin_reset_info(text, bigint)       from public, authenticated;
revoke all on function public.admin_reset_approve(text, bigint, text) from public, authenticated;
revoke all on function public.admin_reset_reject(text, bigint)     from public, authenticated;
grant execute on function public.admin_reset_list(text)               to anon;
grant execute on function public.admin_reset_claim(text, bigint)      to anon;
grant execute on function public.admin_reset_info(text, bigint)       to anon;
grant execute on function public.admin_reset_approve(text, bigint, text) to anon;
grant execute on function public.admin_reset_reject(text, bigint)     to anon;
commit;

-- التراجع (عند الحاجة فقط): يعيد 7أ كما كانت
-- drop function if exists public.admin_reset_reject(text,bigint), public.admin_reset_approve(text,bigint,text),
--   public.admin_reset_info(text,bigint), public.admin_reset_claim(text,bigint), public.admin_reset_list(text);
-- alter table public.reset_requests drop column if exists vcode, drop column if exists handled_at, drop column if exists attempts;
-- (ثم أعد تنفيذ تعريفي reset_request و_reset_housekeeping من 7a_reset_request.sql؛ الأولى كانت مفعّلة بنسختها الأصلية)
