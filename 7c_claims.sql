-- 7ج) المرحلة د: تعارض المشرفين في الشكاوى والملاحظات والاقتراحات والمساعدة + تصحيحات مراجعة 7ب.
-- الحالات للمشرف (محسوبة، دون تغيير القيم القديمة):
--   جديد          = status 'open' وغير مستلَم (أو انتهت مهلة استلامه 15 دقيقة)
--   قيد المعالجة  = status 'open'/'replied' واستلام حيّ (المشرف + زمن الاستلام)
--   منجز          = 'replied' أو 'closed'
--   مرفوض         = 'rejected' (قيمة جديدة)
-- الاستلام ذرّي (update ... where ... returning). الرد/الإغلاق/الرفض لمن استلم فقط وخلال المهلة.
-- يعدّل ثلاث دوال قديمة (admin_messages, admin_reply, my_messages) بموافقة المالك؛ أصولها في قسم التراجع.
begin;

-- 1) أعمدة الاستلام + حالة «مرفوض»
alter table public.messages
  add column claimed_by uuid references public.accounts(id) on delete set null,
  add column claimed_at timestamptz;
alter table public.messages drop constraint messages_status_check;
alter table public.messages add constraint messages_status_check
  check (status in ('open','replied','closed','rejected'));

-- 2) استلام ذرّي: يفوز مشرف واحد؛ الآخر يعرف من استلم ومتى
create or replace function public.admin_msg_claim(p_token text, p_id bigint)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token); m public.messages; who text;
begin
  update public.messages set claimed_by = ad.id, claimed_at = now()
   where id = p_id and status in ('open','replied')
     and (claimed_by is null or claimed_by = ad.id or claimed_at < now() - interval '15 minutes')
  returning * into m;
  if m.id is not null then
    return jsonb_build_object('claimed', true, 'until', m.claimed_at + interval '15 minutes');
  end if;
  select * into m from public.messages where id = p_id;
  if m.id is null then raise exception 'E_ARG'; end if;
  select mill_name into who from public.accounts where id = m.claimed_by;
  return jsonb_build_object('claimed', false, 'by', who, 'at', m.claimed_at, 'status', m.status);
end $function$;

-- 3) ترك الاستلام (لمن استلم فقط)
create or replace function public.admin_msg_release(p_token text, p_id bigint)
 returns void language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  update public.messages set claimed_by = null, claimed_at = null
   where id = p_id and claimed_by = ad.id and status in ('open','replied');
end $function$;

-- 4) [تعديل دالة قديمة] الرد/الإغلاق/الرفض: لمن استلم فقط وخلال 15 دقيقة، وبحالات محددة
create or replace function public.admin_reply(p_token text, p_id bigint, p_reply text, p_status text)
 returns void language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token); st text := coalesce(nullif(p_status,''),'replied');
begin
  if st not in ('replied','closed','rejected') then raise exception 'E_ARG'; end if;
  update public.messages
     set reply = nullif(left(coalesce(p_reply,''),5000),''), status = st, replied_at = now()
   where id = p_id and status in ('open','replied')
     and claimed_by = ad.id and claimed_at >= now() - interval '15 minutes';
  if not found then raise exception 'E_NOT_CLAIMED'; end if;
end $function$;

-- 5) [تعديل دالة قديمة] قائمة المشرف: + اسم المستلم، وهل الاستلام حيّ، وهل هو لي
create or replace function public.admin_messages(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  return coalesce((select jsonb_agg((to_jsonb(m) - 'claimed_by') || jsonb_build_object(
      'mill_name', a.mill_name, 'phone', a.phone,
      'claimed_name', c.mill_name,
      'mine', coalesce(m.claimed_by = ad.id, false),
      'claim_live', m.claimed_by is not null and m.claimed_at >= now() - interval '15 minutes')
      order by (m.status = 'open') desc, m.created_at desc)
    from public.messages m
    join public.accounts a on a.id = m.account_id
    left join public.accounts c on c.id = m.claimed_by), '[]'::jsonb);
end $function$;

-- 6) [تعديل دالة قديمة] رسائل المطحنة: لا تظهر لها بيانات استلام المشرفين
create or replace function public.my_messages(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct(p_token);
begin
  return coalesce((select jsonb_agg(to_jsonb(m) - 'account_id' - 'claimed_by' - 'claimed_at' order by m.created_at desc)
    from public.messages m where m.account_id = a.id), '[]'::jsonb);
end $function$;

-- 7) تصحيحات مراجعة 7ب (دوال أُنشئت في 7أ/7ب):
-- 7-أ) رمز تحقق بلا انحياز (رفض القيم ≥ 60000 قبل باقي القسمة على 10000)
create or replace function public.reset_request(p_phone text, p_new text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ph text := public._digits(p_phone); a public.accounts; vc text; b bytea; n int;
begin
  if length(coalesce(p_new,'')) < 6 then raise exception 'E_WEAK_PASS'; end if;
  perform public._reset_housekeeping();
  if (select count(*) from public.reset_requests where created_at > now() - interval '1 hour') >= 30 then raise exception 'E_RATE'; end if;
  select * into a from public.accounts where phone = ph and role = 'mill';
  if a.id is null then raise exception 'E_NO_ACCOUNT'; end if;
  perform pg_advisory_xact_lock(hashtext('reset:' || a.id::text));
  if (select count(*) from public.reset_requests where account_id = a.id and created_at > now() - interval '1 hour') >= 3 then raise exception 'E_RATE'; end if;
  loop
    b := extensions.gen_random_bytes(2); n := get_byte(b,0) * 256 + get_byte(b,1);
    exit when n < 60000;
  end loop;
  vc := lpad((n % 10000)::text, 4, '0');
  insert into public.reset_requests(account_id, new_hash, vcode)
   values (a.id, extensions.crypt(p_new, extensions.gen_salt('bf', 10)), vc);
  return jsonb_build_object('ok', true, 'code', vc);
end $function$;

-- 7-ب) المعلومات: تنظيف أولًا (لا يقرأ مستلِم انتهت مهلته)
create or replace function public.admin_reset_info(p_token text, p_id bigint)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token); r public.reset_requests; a public.accounts; s public.acct_stats;
begin
  perform public._reset_housekeeping();
  select * into r from public.reset_requests where id = p_id and status = 'processing' and claimed_by = ad.id;
  if r.id is null then raise exception 'E_NOT_CLAIMED'; end if;
  select * into a from public.accounts where id = r.account_id;
  select * into s from public.acct_stats where account_id = a.id;
  return jsonb_build_object('name', a.mill_name, 'phone', a.phone, 'phone2', a.phone2, 'created_at', a.created_at,
    'last_login', a.last_login, 'paid_until', a.paid_until, 'status', a.status,
    'invoices', coalesce(s.invoices, 0), 'customers', coalesce(s.customers, 0));
end $function$;

-- 7-ج) الموافقة: لا «تم» إن لم يتغير حساب مطحنة فعلًا، ولا بصمة فارغة
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
    return jsonb_build_object('error', 'E_VCODE');
  end if;
  if r.new_hash is null then raise exception 'E_REQUEST'; end if;
  update public.accounts set pass_hash = r.new_hash, failed_count = 0, locked_until = null where id = r.account_id and role = 'mill';
  if not found then raise exception 'E_REQUEST'; end if;
  delete from public.sessions where account_id = r.account_id;
  update public.reset_requests set status = 'done', new_hash = null, vcode = null, handled_at = now() where id = r.id;
  update public.reset_requests set status = 'expired', new_hash = null, vcode = null
   where account_id = r.account_id and status in ('new','processing') and id <> r.id;
  return jsonb_build_object('ok', true);
end $function$;

-- الصلاحيات (الدوال القديمة تحتفظ بصلاحياتها مع create or replace)
revoke all on function public.admin_msg_claim(text, bigint)   from public, authenticated;
revoke all on function public.admin_msg_release(text, bigint) from public, authenticated;
grant execute on function public.admin_msg_claim(text, bigint)   to anon;
grant execute on function public.admin_msg_release(text, bigint) to anon;
commit;

-- ===================== التراجع (عند الحاجة فقط) =====================
-- begin;
-- drop function if exists public.admin_msg_claim(text, bigint), public.admin_msg_release(text, bigint);
-- -- الدوال القديمة كما كانت قبل 7ج:
-- create or replace function public.admin_reply(p_token text, p_id bigint, p_reply text, p_status text)
--  returns void language plpgsql security definer set search_path to '' as $function$
-- declare ad public.accounts := public._admin(p_token);
-- begin
--   update public.messages set reply=nullif(left(coalesce(p_reply,''),5000),''), status=coalesce(nullif(p_status,''),'replied'), replied_at=now() where id=p_id;
-- end $function$;
-- create or replace function public.admin_messages(p_token text)
--  returns jsonb language plpgsql security definer set search_path to '' as $function$
-- declare ad public.accounts := public._admin(p_token);
-- begin
--   return coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('mill_name',a.mill_name,'phone',a.phone) order by (m.status='open') desc, m.created_at desc)
--     from public.messages m join public.accounts a on a.id=m.account_id),'[]'::jsonb);
-- end $function$;
-- create or replace function public.my_messages(p_token text)
--  returns jsonb language plpgsql security definer set search_path to '' as $function$
-- declare a public.accounts := public._acct(p_token);
-- begin
--   return coalesce((select jsonb_agg(to_jsonb(m)-'account_id' order by m.created_at desc) from public.messages m where m.account_id=a.id),'[]'::jsonb);
-- end $function$;
-- -- «مرفوض» غير موجودة في القيد القديم: تتحول الرسائل المرفوضة إلى «مغلقة» قبل إعادته
-- update public.messages set status = 'closed' where status = 'rejected';
-- alter table public.messages drop constraint messages_status_check;
-- alter table public.messages add constraint messages_status_check check (status in ('open','replied','closed'));
-- alter table public.messages drop column if exists claimed_by, drop column if exists claimed_at;
-- -- دوال الاستعادة: أعد تنفيذ تعريفات reset_request وadmin_reset_info وadmin_reset_approve من 7b_reset_admin.sql
-- commit;
