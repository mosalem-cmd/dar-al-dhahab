-- اختبار رجوع للمرحلة 7ب: يفترض أن 7أ مطبّقة. كل شيء داخل معاملة تُلغى بخطأ مقصود، ولا يبقى أثر.
-- يُشغَّل بعد موافقة المالك فقط. الحسابات المؤقتة وهمية (99900000011/12/18/19).
do $t$
declare mig text := $m$

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
$m$;
begin
 execute mig;
 execute $x$
do $u$

declare ma uuid; mb uuid; ad1 uuid; ad2 uuid; t1 text; t2 text; tm text; r jsonb; n int; res text := ''; idA bigint; idB bigint; idC bigint; vA text; vB text; st text; hs text; info jsonb;
begin
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000011',extensions.crypt('oldpass1',extensions.gen_salt('bf',4)),'TEST A','mill') returning id into ma;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000012',extensions.crypt('oldpass2',extensions.gen_salt('bf',4)),'TEST B','mill') returning id into mb;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000019',extensions.crypt('adminpass',extensions.gen_salt('bf',4)),'TEST ADMIN 1','admin') returning id into ad1;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000018',extensions.crypt('adminpass',extensions.gen_salt('bf',4)),'TEST ADMIN 2','admin') returning id into ad2;
 insert into public.admin_phones(phone) values ('99900000019'),('99900000018');
 t1 := public._new_session(ad1); t2 := public._new_session(ad2); tm := public._new_session(ma); perform public._new_session(ma);
 -- طلب الضحية ثم طلب المهاجم لنفس الرقم
 r := public.reset_request('99900000011','victimpass'); vA := r->>'code';
 res := res || chr(10) || (case when vA ~ '^[0-9]{4}$' and r->>'ok'='true' then 'PASS ' else 'FAIL ' end || '01 request returns a 4-digit verification code');
 r := public.reset_request('99900000011','attackerpass'); vB := r->>'code';
 select id into idA from public.reset_requests where account_id=ma order by id limit 1; select id into idB from public.reset_requests where account_id=ma order by id desc limit 1;
 update public.reset_requests set vcode='1111' where id=idA; update public.reset_requests set vcode='2222' where id=idB;
 res := res || chr(10) || (case when idA<>idB and (select count(*) from public.reset_requests where account_id=ma and status='new')=2 then 'PASS ' else 'FAIL ' end || '02 a second request does NOT cancel the first');
 -- صلاحيات
 begin perform public.admin_reset_list(tm); res := res || chr(10) || 'FAIL 03 mill token read the list'; exception when others then res := res || chr(10) || ('PASS 03 mill token refused: '||sqlerrm); end;
 begin perform public.admin_reset_claim(tm,idA); res := res || chr(10) || 'FAIL 03b mill token claimed'; exception when others then res := res || chr(10) || 'PASS 03b mill token cannot claim'; end;
 begin perform public.admin_reset_list('bad'); res := res || chr(10) || 'FAIL 03c bad token'; exception when others then res := res || chr(10) || 'PASS 03c bad token refused'; end;
 -- القائمة
 info := public.admin_reset_list(t1);
 res := res || chr(10) || (case when jsonb_array_length(info)=2 and (info->0->>'n24')::int=2 and not (info->0 ? 'vcode') and not (info->0 ? 'new_hash') then 'PASS ' else 'FAIL ' end || '04 list: 2 requests, n24=2, no vcode/hash exposed');
 -- معلومات قبل الاستلام
 begin perform public.admin_reset_info(t1,idA); res := res || chr(10) || 'FAIL 05 info before claim'; exception when others then res := res || chr(10) || (case when sqlerrm='E_NOT_CLAIMED' then 'PASS ' else 'FAIL ' end || '05 info refused before claiming'); end;
 -- استلام ذرّي
 r := public.admin_reset_claim(t1,idA);
 res := res || chr(10) || (case when r->>'claimed'='true' then 'PASS ' else 'FAIL ' end || '06 admin 1 claims request A');
 r := public.admin_reset_claim(t2,idA);
 res := res || chr(10) || (case when r->>'claimed'='false' and r->>'by'='TEST ADMIN 1' then 'PASS ' else 'FAIL ' end || '07 admin 2 cannot claim; told who has it');
 begin perform public.admin_reset_approve(t2,idA,'1111'); res := res || chr(10) || 'FAIL 08 non-claimant approved'; exception when others then res := res || chr(10) || (case when sqlerrm='E_NOT_CLAIMED' then 'PASS ' else 'FAIL ' end || '08 non-claimant cannot approve'); end;
 begin perform public.admin_reset_reject(t2,idA); res := res || chr(10) || 'FAIL 08b non-claimant rejected'; exception when others then res := res || chr(10) || (case when sqlerrm='E_NOT_CLAIMED' then 'PASS ' else 'FAIL ' end || '08b non-claimant cannot reject'); end;
 begin perform public.admin_reset_info(t2,idA); res := res || chr(10) || 'FAIL 08c non-claimant info'; exception when others then res := res || chr(10) || 'PASS 08c non-claimant cannot read info'; end;
 info := public.admin_reset_info(t1,idA);
 res := res || chr(10) || (case when info->>'name'='TEST A' and info ? 'invoices' and info ? 'customers' and not (info ? 'net') and not (info ? 'grams') then 'PASS ' else 'FAIL ' end || '09 info: basics only, no customer gold/net');
 -- ثغرة الاستبدال: رمز الضحية لا يعتمد طلب المهاجم
 r := public.admin_reset_claim(t1,idB);
 r := public.admin_reset_approve(t1,idB,'1111');
 res := res || chr(10) || (case when r->>'error'='E_VCODE' and (select pass_hash=extensions.crypt('oldpass1',pass_hash) from public.accounts where id=ma) then 'PASS ' else 'FAIL ' end || '10 victim code cannot approve the attacker request; password unchanged');
 res := res || chr(10) || (case when (select attempts from public.reset_requests where id=idB)=1 then 'PASS ' else 'FAIL ' end || '10b wrong-code attempt is counted (not rolled back)');
 perform public.admin_reset_approve(t1,idB,'0000'); r := public.admin_reset_approve(t1,idB,'9999');
 select status,new_hash into st,hs from public.reset_requests where id=idB;
 res := res || chr(10) || (case when st='rejected' and hs is null then 'PASS ' else 'FAIL ' end || '11 three wrong codes reject the request and drop its hash');
 -- موافقة صحيحة
 r := public.admin_reset_approve(t1,idA,'1111');
 res := res || chr(10) || (case when r->>'ok'='true' then 'PASS ' else 'FAIL ' end || '12 correct code approves');
 res := res || chr(10) || (case when (select pass_hash=extensions.crypt('victimpass',pass_hash) and pass_hash<>extensions.crypt('oldpass1',pass_hash) and failed_count=0 and locked_until is null from public.accounts where id=ma) then 'PASS ' else 'FAIL ' end || '13 the owner''s own chosen password is now active');
 res := res || chr(10) || (case when not exists(select 1 from public.sessions where account_id=ma) then 'PASS ' else 'FAIL ' end || '14 all old sessions of the account are closed');
 res := res || chr(10) || (case when (select status from public.reset_requests where id=idA)='done' and (select new_hash is null and vcode is null from public.reset_requests where id=idA) then 'PASS ' else 'FAIL ' end || '15 request done; hash and code erased');
 begin perform public.admin_reset_approve(t1,idA,'1111'); res := res || chr(10) || 'FAIL 16 approved twice'; exception when others then res := res || chr(10) || 'PASS 16 an approved request cannot be approved again'; end;
 -- رفض
 perform public.reset_request('99900000012','rejectme1'); select id into idC from public.reset_requests where account_id=mb;
 begin perform public.admin_reset_reject(t1,idC); res := res || chr(10) || 'FAIL 17 rejected unclaimed'; exception when others then res := res || chr(10) || 'PASS 17 cannot reject without claiming'; end;
 perform public.admin_reset_claim(t1,idC); perform public.admin_reset_reject(t1,idC);
 res := res || chr(10) || (case when (select status from public.reset_requests where id=idC)='rejected' and (select pass_hash=extensions.crypt('oldpass2',pass_hash) from public.accounts where id=mb) then 'PASS ' else 'FAIL ' end || '18 reject leaves the account untouched');
 -- انتهاء الاستلام بعد 15 دقيقة
 perform public.admin_reset_list(t1);
 update public.reset_requests set status='new', claimed_by=null where false;
 insert into public.reset_requests(account_id,new_hash,vcode,status,claimed_by,claimed_at) values (mb,extensions.crypt('x12345',extensions.gen_salt('bf',4)),'3333','processing',ad1,now()-interval '16 minutes') returning id into idC;
 perform public.admin_reset_list(t2);
 res := res || chr(10) || (case when (select status='new' and claimed_by is null from public.reset_requests where id=idC) then 'PASS ' else 'FAIL ' end || '19 a claim older than 15 minutes is released');
 r := public.admin_reset_claim(t2,idC);
 res := res || chr(10) || (case when r->>'claimed'='true' then 'PASS ' else 'FAIL ' end || '20 after release another admin can claim');
 -- انتهاء 24 ساعة
 update public.reset_requests set expires_at=now()-interval '1 minute' where id=idC;
 perform public.admin_reset_list(t2);
 res := res || chr(10) || (case when (select status='expired' and new_hash is null from public.reset_requests where id=idC) then 'PASS ' else 'FAIL ' end || '21 expired request loses its hash');
 begin perform public.admin_reset_approve(t2,idC,'3333'); res := res || chr(10) || 'FAIL 22 approved expired'; exception when others then res := res || chr(10) || 'PASS 22 expired request cannot be approved'; end;
 -- صلاحيات الدوال
 res := res || chr(10) || (case when (select bool_and(has_function_privilege('anon',p.oid,'execute') and not has_function_privilege('authenticated',p.oid,'execute')) from pg_proc p where pronamespace='public'::regnamespace and proname in ('admin_reset_list','admin_reset_claim','admin_reset_info','admin_reset_approve','admin_reset_reject','reset_request','reset_password' ) and proname<>'reset_password')
   and not has_function_privilege('anon','public._reset_housekeeping()','execute') then 'PASS ' else 'FAIL ' end || '23 grants: anon only on public functions; helper closed');
 res := res || chr(10) || (case when (select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc where pronamespace='public'::regnamespace and proname in ('admin_reset_list','admin_reset_claim','admin_reset_info','admin_reset_approve','admin_reset_reject','reset_request','_reset_housekeeping')) then 'PASS ' else 'FAIL ' end || '24 all functions security definer with empty search_path');
 raise exception E'ROLLBACK_TEST_RESULT\n%', res;
end

$u$
$x$;
end
$t$;
