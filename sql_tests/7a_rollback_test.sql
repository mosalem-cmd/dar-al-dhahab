-- اختبار رجوع للمرحلة 7أ: كل شيء داخل معاملة تُلغى بخطأ مقصود في النهاية، ولا يبقى أثر.
-- يُشغَّل بعد موافقة المالك فقط. أرقام الحسابات المؤقتة وهمية (99900000011/12/19).
do $t$
declare mig text := $m$

create table public.reset_requests (
  id          bigint generated always as identity primary key,
  account_id  uuid not null references public.accounts(id) on delete cascade,
  new_hash    text,                                   -- بصمة كلمة السر التي اختارها صاحب الحساب (لا نص صريح أبدًا)
  status      text not null default 'new'
              check (status in ('new','processing','done','rejected','expired')),
  claimed_by  uuid references public.accounts(id),    -- للمرحلة د (استلام المشرف)
  claimed_at  timestamptz,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours'
);
create index on public.reset_requests (account_id, created_at);
create index on public.reset_requests (status, created_at);
alter table public.reset_requests enable row level security;      -- بلا سياسات: لا وصول مباشر
revoke all on public.reset_requests from anon, authenticated;

create or replace function public.reset_request(p_phone text, p_new text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ph text := public._digits(p_phone); a public.accounts;
begin
  if length(coalesce(p_new,'')) < 6 then raise exception 'E_WEAK_PASS'; end if;
  -- تنظيف: ينتهي ما تجاوز 24 ساعة، ويُحذف ما مضى عليه 7 أيام
  update public.reset_requests set status = 'expired', new_hash = null
   where status in ('new','processing') and expires_at < now();
  delete from public.reset_requests where created_at < now() - interval '7 days';
  -- سقف عام ضد الإغراق
  if (select count(*) from public.reset_requests where created_at > now() - interval '1 hour') >= 30 then
    raise exception 'E_RATE';
  end if;
  select * into a from public.accounts where phone = ph and role = 'mill';
  if a.id is null then raise exception 'E_NO_ACCOUNT'; end if;                       -- «يرجى إدخال رقم الحساب بشكل صحيح»
  -- 3 طلبات في الساعة لكل حساب
  if (select count(*) from public.reset_requests where account_id = a.id and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'E_RATE';
  end if;
  -- طلب يعالجه مشرف الآن: لا يُستبدل
  if exists (select 1 from public.reset_requests where account_id = a.id and status = 'processing' and expires_at > now()) then
    raise exception 'E_BUSY';
  end if;
  -- الطلب الجديد يحلّ محل طلب «جديد» سابق لنفس الحساب (آخر كلمة سر كتبها هي المعتمدة)
  update public.reset_requests set status = 'expired', new_hash = null where account_id = a.id and status = 'new';
  insert into public.reset_requests(account_id, new_hash)
   values (a.id, extensions.crypt(p_new, extensions.gen_salt('bf', 10)));
  return jsonb_build_object('ok', true);
end $function$;

revoke all on function public.reset_request(text, text) from public, authenticated;
grant execute on function public.reset_request(text, text) to anon;
$m$;
begin
 execute mig;
 execute $x$
do $u$

declare ma uuid; mb uuid; ad uuid; r jsonb; n int; res text[] := '{}'; hs text; st text; e text;
begin
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000011',extensions.crypt('oldpass1',extensions.gen_salt('bf',4)),'TEST A','mill') returning id into ma;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000012',extensions.crypt('oldpass2',extensions.gen_salt('bf',4)),'TEST B','mill') returning id into mb;
 insert into public.accounts(phone,pass_hash,mill_name,role) values ('99900000019',extensions.crypt('adminpass',extensions.gen_salt('bf',4)),'TEST ADMIN','admin') returning id into ad;
 begin perform public.reset_request('99900000000','secret123'); res := res || 'FAIL 01 unknown number accepted'; exception when others then res := res || (case when sqlerrm='E_NO_ACCOUNT' then 'PASS ' else 'FAIL ' end || '01 unknown number refused: '||sqlerrm); end;
 begin perform public.reset_request('99900000019','secret123'); res := res || 'FAIL 02 admin number accepted'; exception when others then res := res || (case when sqlerrm='E_NO_ACCOUNT' then 'PASS ' else 'FAIL ' end || '02 admin number refused: '||sqlerrm); end;
 begin perform public.reset_request('99900000011','123'); res := res || 'FAIL 03 weak password accepted'; exception when others then res := res || (case when sqlerrm='E_WEAK_PASS' then 'PASS ' else 'FAIL ' end || '03 weak password refused'); end;
 select count(*) into n from public.reset_requests; res := res || (case when n=0 then 'PASS ' else 'FAIL ' end || '04 nothing stored by refused calls');
 r := public.reset_request('999 000 000 11','newpass11');
 select status,new_hash into st,hs from public.reset_requests where account_id=ma;
 res := res || (case when r->>'ok'='true' and st='new' and hs is not null and hs<>'newpass11' and hs=extensions.crypt('newpass11',hs) then 'PASS ' else 'FAIL ' end || '05 valid request: status new, only a bcrypt hash stored');
 res := res || (case when (select pass_hash=extensions.crypt('oldpass1',pass_hash) from public.accounts where id=ma) then 'PASS ' else 'FAIL ' end || '06 account password NOT changed by a request');
 perform public.reset_request('99900000011','newpass22');
 select count(*) into n from public.reset_requests where account_id=ma and status='new';
 res := res || (case when n=1 and (select new_hash=extensions.crypt('newpass22',new_hash) from public.reset_requests where account_id=ma and status='new') and (select count(*) from public.reset_requests where account_id=ma and status='expired')=1 then 'PASS ' else 'FAIL ' end || '07 second request replaces the first (one open request, latest password)');
 perform public.reset_request('99900000011','newpass33');
 begin perform public.reset_request('99900000011','newpass44'); res := res || 'FAIL 08 4th request in an hour accepted'; exception when others then res := res || (case when sqlerrm='E_RATE' then 'PASS ' else 'FAIL ' end || '08 per-account limit: 4th request in an hour refused'); end;
 update public.reset_requests set status='processing' where account_id=ma and status='new';
 update public.reset_requests set created_at=now()-interval '2 hours' where account_id=ma;
 begin perform public.reset_request('99900000011','newpass55'); res := res || 'FAIL 09 replaced a request being processed'; exception when others then res := res || (case when sqlerrm='E_BUSY' then 'PASS ' else 'FAIL ' end || '09 request being processed by an admin is not replaced'); end;
 update public.reset_requests set expires_at=now()-interval '1 minute' where account_id=ma and status='processing';
 perform public.reset_request('99900000012','newpass11');
 res := res || (case when (select status from public.reset_requests where account_id=ma and new_hash is null order by id desc limit 1) in ('expired') then 'PASS ' else 'FAIL ' end || '10 expired requests lose their hash');
 insert into public.reset_requests(account_id,status) select mb,'done' from generate_series(1,30);
 begin perform public.reset_request('99900000011','newpass11'); res := res || 'FAIL 11 global cap not enforced'; exception when others then res := res || (case when sqlerrm='E_RATE' then 'PASS ' else 'FAIL ' end || '11 global cap (30/hour) enforced'); end;
 res := res || (case when has_function_privilege('anon','public.reset_request(text,text)','execute') and not has_function_privilege('authenticated','public.reset_request(text,text)','execute')
   and not has_table_privilege('anon','public.reset_requests','select') and not has_table_privilege('anon','public.reset_requests','insert') and not has_table_privilege('authenticated','public.reset_requests','select') then 'PASS ' else 'FAIL ' end || '12 grants: anon can only call the function; table closed');
 res := res || (case when (select relrowsecurity from pg_class where oid='public.reset_requests'::regclass) and (select prosecdef and proconfig @> array['search_path=""'] from pg_proc where proname='reset_request' and pronamespace='public'::regnamespace) then 'PASS ' else 'FAIL ' end || '13 RLS on, function security definer with empty search_path');
 raise exception E'ROLLBACK_TEST_RESULT\n%', array_to_string(res, E'\n');
end

$u$
$x$;
end
$t$;
