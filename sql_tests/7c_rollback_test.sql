-- اختبار رجوع للمرحلة د (7ج): يفترض 7أ و7ب مطبّقتين. كل شيء داخل معاملة تُلغى بخطأ مقصود، ولا يبقى أثر.
-- يُشغَّل بعد موافقة المالك فقط. الحسابات والرسائل المؤقتة وهمية (99900000011..19).
do $t$
declare mig text := $m$

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
$m$;
begin
 execute mig;
 execute $x$
do $u$

declare ma uuid; mb uuid; mc uuid; md uuid; ad1 uuid; ad2 uuid; t1 text; t2 text; tm text; r jsonb; n int; res text := ''; m1 bigint; m2 bigint; q bigint; st text; ok boolean; j jsonb; e text;
begin
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000011',extensions.crypt('oldpass1',extensions.gen_salt('bf',4)),'TEST A','mill') returning id into ma;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000012',extensions.crypt('oldpass2',extensions.gen_salt('bf',4)),'TEST B','mill') returning id into mb;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000013',extensions.crypt('oldpass3',extensions.gen_salt('bf',4)),'TEST C','mill') returning id into mc;
 insert into public.accounts(phone,pass_hash,mill_name,role,failed_count,locked_until) values ('99900000014',extensions.crypt('oldpass4',extensions.gen_salt('bf',4)),'TEST D','mill',4,now()+interval '1 hour') returning id into md;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000019',extensions.crypt('adminpass',extensions.gen_salt('bf',4)),'TEST ADMIN 1','admin') returning id into ad1;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000018',extensions.crypt('adminpass',extensions.gen_salt('bf',4)),'TEST ADMIN 2','admin') returning id into ad2;
 insert into public.admin_phones(phone) values ('99900000019'),('99900000018');
 t1 := public._new_session(ad1); t2 := public._new_session(ad2); tm := public._new_session(ma); perform public._new_session(mb); perform public._new_session(md);
 insert into public.messages(account_id,kind,subject,body) values (ma,'complaint','s1','b1') returning id into m1;
 insert into public.messages(account_id,kind,subject,body) values (ma,'help','sub','b2') returning id into m2;
 -- الاستلام
 begin perform public.admin_msg_claim(tm,m1); res := res||chr(10)||'FAIL 01 mill token claimed'; exception when others then res := res||chr(10)||(case when sqlerrm='E_FORBIDDEN' then 'PASS ' else 'FAIL ' end||'01 mill token cannot claim: '||sqlerrm); end;
 r := public.admin_msg_claim(t1,m1);
 res := res||chr(10)||(case when r->>'claimed'='true' then 'PASS ' else 'FAIL ' end||'02 admin 1 claims message 1');
 r := public.admin_msg_claim(t2,m1);
 res := res||chr(10)||(case when r->>'claimed'='false' and r->>'by'='TEST ADMIN 1' and r->>'at' is not null then 'PASS ' else 'FAIL ' end||'03 admin 2 refused, told who and since when');
 begin perform public.admin_reply(t2,m1,'x','replied'); res := res||chr(10)||'FAIL 04 non-claimant replied'; exception when others then res := res||chr(10)||(case when sqlerrm='E_NOT_CLAIMED' and (select reply is null and status='open' from public.messages where id=m1) then 'PASS ' else 'FAIL ' end||'04 non-claimant cannot reply; message unchanged'); end;
 begin perform public.admin_reply(t1,m1,'x','bogus'); res := res||chr(10)||'FAIL 05 bad status accepted'; exception when others then res := res||chr(10)||(case when sqlerrm='E_ARG' then 'PASS ' else 'FAIL ' end||'05 unknown status refused'); end;
 begin perform public.admin_reply(tm,m1,'x','replied'); res := res||chr(10)||'FAIL 05b mill replied'; exception when others then res := res||chr(10)||(case when sqlerrm='E_FORBIDDEN' then 'PASS ' else 'FAIL ' end||'05b mill token cannot reply'); end;
 perform public.admin_reply(t1,m1,'الرد','replied');
 res := res||chr(10)||(case when (select status='replied' and reply='الرد' from public.messages where id=m1) then 'PASS ' else 'FAIL ' end||'06 claimant replies');
 j := (select x from jsonb_array_elements(public.admin_messages(t1)) x where (x->>'id')::bigint=m1);
 res := res||chr(10)||(case when (j->>'mine')::boolean and (j->>'claim_live')::boolean and j->>'claimed_name'='TEST ADMIN 1' and not (j ? 'claimed_by') and j->>'mill_name'='TEST A' then 'PASS ' else 'FAIL ' end||'07 admin list: mine, live claim, claimant name; no raw claimed_by');
 j := (select x from jsonb_array_elements(public.admin_messages(t2)) x where (x->>'id')::bigint=m1);
 res := res||chr(10)||(case when not (j->>'mine')::boolean and (j->>'claim_live')::boolean then 'PASS ' else 'FAIL ' end||'08 other admin sees it as taken');
 j := (select x from jsonb_array_elements(public.my_messages(tm)) x where (x->>'id')::bigint=m1);
 res := res||chr(10)||(case when not (j ? 'claimed_by') and not (j ? 'claimed_at') and not (j ? 'account_id') and j->>'reply'='الرد' then 'PASS ' else 'FAIL ' end||'09 mill sees its reply but no admin claim data');
 -- انتهاء المهلة
 update public.messages set claimed_at = now() - interval '16 minutes' where id=m1;
 r := public.admin_msg_claim(t2,m1);
 res := res||chr(10)||(case when r->>'claimed'='true' then 'PASS ' else 'FAIL ' end||'10 after 15 minutes another admin can claim');
 begin perform public.admin_reply(t1,m1,'y','closed'); res := res||chr(10)||'FAIL 10b old claimant still acts'; exception when others then res := res||chr(10)||(case when sqlerrm='E_NOT_CLAIMED' then 'PASS ' else 'FAIL ' end||'10b old claimant locked out after expiry'); end;
 perform public.admin_reply(t2,m1,'مرفوض لعدم الوضوح','rejected');
 res := res||chr(10)||(case when (select status from public.messages where id=m1)='rejected' then 'PASS ' else 'FAIL ' end||'11 reject is a valid final status');
 r := public.admin_msg_claim(t1,m1);
 res := res||chr(10)||(case when r->>'claimed'='false' and r->>'status'='rejected' then 'PASS ' else 'FAIL ' end||'12 a rejected message cannot be claimed again');
 begin perform public.admin_reply(t2,m1,'z','replied'); res := res||chr(10)||'FAIL 12b replied after reject'; exception when others then res := res||chr(10)||(case when sqlerrm='E_NOT_CLAIMED' then 'PASS ' else 'FAIL ' end||'12b no action on a final message'); end;
 -- ترك الاستلام
 perform public.admin_msg_claim(t1,m2); perform public.admin_msg_release(t2,m2);
 res := res||chr(10)||(case when (select claimed_by from public.messages where id=m2)=ad1 then 'PASS ' else 'FAIL ' end||'13 non-claimant cannot release');
 perform public.admin_msg_release(t1,m2);
 res := res||chr(10)||(case when (select claimed_by is null and claimed_at is null from public.messages where id=m2) then 'PASS ' else 'FAIL ' end||'14 claimant releases');
 r := public.admin_msg_claim(t2,m2); perform public.admin_reply(t2,m2,'','closed');
 res := res||chr(10)||(case when r->>'claimed'='true' and (select status from public.messages where id=m2)='closed' then 'PASS ' else 'FAIL ' end||'15 released message claimed and closed by admin 2');
 begin perform public.admin_overview(t1); perform public.admin_help_stats(t1); res := res||chr(10)||'PASS 16 overview and help stats still work'; exception when others then res := res||chr(10)||'FAIL 16 overview/help stats: '||sqlerrm; end;
 -- تصحيحات 7ب
 ok := true;
 for i in 1..3 loop r := public.reset_request('99900000012','newpass'||i); ok := ok and (r->>'code') ~ '^[0-9]{4}$'; end loop;
 res := res||chr(10)||(case when ok then 'PASS ' else 'FAIL ' end||'17 verification codes are 4 digits');
 perform public.reset_request('99900000013','newpassc'); select id into q from public.reset_requests where account_id=mc;
 perform public.admin_reset_claim(t1,q); update public.reset_requests set claimed_at=now()-interval '16 minutes' where id=q;
 begin perform public.admin_reset_info(t1,q); res := res||chr(10)||'FAIL 18 expired claimant read info'; exception when others then res := res||chr(10)||(case when sqlerrm='E_NOT_CLAIMED' then 'PASS ' else 'FAIL ' end||'18 info refused after the claim expired'); end;
 perform public.admin_reset_claim(t1,q); update public.reset_requests set vcode='5555' where id=q; update public.accounts set role='admin' where id=mc;
 begin perform public.admin_reset_approve(t1,q,'5555'); res := res||chr(10)||'FAIL 19 approved for a non-mill account'; exception when others then res := res||chr(10)||(case when sqlerrm='E_REQUEST' and (select status='processing' from public.reset_requests where id=q) and (select pass_hash=extensions.crypt('oldpass3',pass_hash) from public.accounts where id=mc) then 'PASS ' else 'FAIL ' end||'19 no account changed: error, request untouched'); end;
 update public.accounts set role='mill' where id=mc;
 perform public.reset_request('99900000014','newpassd'); select id into q from public.reset_requests where account_id=md;
 perform public.admin_reset_claim(t1,q); update public.reset_requests set vcode='7777' where id=q;
 r := public.admin_reset_approve(t1,q,'7777');
 res := res||chr(10)||(case when r->>'ok'='true' and (select failed_count=0 and locked_until is null and pass_hash=extensions.crypt('newpassd',pass_hash) from public.accounts where id=md) then 'PASS ' else 'FAIL ' end||'20 approve resets a real lock (4 failures + lock) and sets the new password');
 res := res||chr(10)||(case when not exists(select 1 from public.sessions where account_id=md) and exists(select 1 from public.sessions where account_id=mb) and exists(select 1 from public.sessions where token=t1) then 'PASS ' else 'FAIL ' end||'21 only that account''s sessions closed (others and admin intact)');
 begin perform public.admin_reset_approve(t1,q,'7777'); res := res||chr(10)||'FAIL 22 approved twice'; exception when others then res := res||chr(10)||(case when sqlerrm='E_NOT_CLAIMED' then 'PASS ' else 'FAIL ' end||'22 second approval refused with E_NOT_CLAIMED'); end;
 -- الصلاحيات والقيود
 res := res||chr(10)||(case when has_function_privilege('anon','public.admin_msg_claim(text,bigint)','execute') and has_function_privilege('anon','public.admin_msg_release(text,bigint)','execute')
   and not has_function_privilege('authenticated','public.admin_msg_claim(text,bigint)','execute') and not has_function_privilege('authenticated','public.admin_msg_release(text,bigint)','execute')
   and has_function_privilege('anon','public.admin_reply(text,bigint,text,text)','execute') and has_function_privilege('anon','public.my_messages(text)','execute') and has_function_privilege('anon','public.admin_messages(text)','execute') then 'PASS ' else 'FAIL ' end||'23 grants: new functions anon only; old ones keep their access');
 res := res||chr(10)||(case when (select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc where pronamespace='public'::regnamespace and proname in ('admin_msg_claim','admin_msg_release','admin_reply','admin_messages','my_messages','reset_request','admin_reset_info','admin_reset_approve')) then 'PASS ' else 'FAIL ' end||'24 every touched function: security definer, empty search_path');
 res := res||chr(10)||(case when (select pg_get_constraintdef(oid) like '%rejected%' from pg_constraint where conname='messages_status_check' and conrelid='public.messages'::regclass) then 'PASS ' else 'FAIL ' end||'25 status check allows rejected');
 raise exception E'ROLLBACK_TEST_RESULT\n%', res;
end

$u$
$x$;
end
$t$;
