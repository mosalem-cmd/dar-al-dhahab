-- دار الذهب: إصلاحات الأمان والاشتراك (نسخة 2.2.0)
-- يُنفَّذ مرة واحدة في Supabase → SQL Editor. آمن للتكرار.
begin;

-- 1) لوحة المشرف لا تتعطل بسبب عدد غرامات مكتوب بخطأ (مثل 1.2.3)
create or replace function public._num(p text)
returns numeric language sql immutable set search_path to '' as $$
  select case when regexp_replace(coalesce(p,''),'[^0-9.]','','g') ~ '^[0-9]+(\.[0-9]+)?$'
              then regexp_replace(coalesce(p,''),'[^0-9.]','','g')::numeric else 0 end
$$;
revoke all on function public._num(text) from public, anon, authenticated;

create or replace function public.admin_overview(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  return jsonb_build_object(
    'mills',(select count(*) from public.accounts where role='mill'),
    'active',(select count(*) from public.accounts where role='mill' and status='active'),
    'suspended',(select count(*) from public.accounts where role='mill' and status='suspended'),
    'active7',(select count(*) from public.accounts where role='mill' and greatest(last_login,last_sync)>now()-interval '7 days'),
    'codes_free',(select count(*) from public.approval_codes where used_by is null and not revoked and (expires_at is null or expires_at>now())),
    'msgs_open',(select count(*) from public.messages where status='open'),
    'pay_pending',(select count(*) from public.payments where status='pending'),
    'pay_confirmed_sum',(select coalesce(sum(amount),0) from public.payments where status='confirmed'),
    'invoices',(select count(*) from public.docs d join public.accounts a on a.id=d.account_id where a.role='mill' and d.path like 'invoices/%'),
    'grams',(select coalesce(sum(public._num(d.data->>'grams')),0) from public.docs d join public.accounts a on a.id=d.account_id where a.role='mill' and d.path like 'invoices/%'),
    'sub_expired',(select count(*) from public.accounts where role='mill' and paid_until is not null and paid_until<current_date),
    'sub_soon',(select count(*) from public.accounts where role='mill' and paid_until is not null and paid_until>=current_date and paid_until<=current_date+7),
    'sub_none',(select count(*) from public.accounts where role='mill' and paid_until is null),
    'setup_due',(select count(*) from public.accounts a where a.role='mill' and a.setup_fee > (select coalesce(sum(p.amount),0) from public.payments p where p.account_id=a.id and p.kind='setup' and p.status='confirmed')));
end $function$;

-- 2) سجل المدفوعات يبقى بعد حذف المطحنة لحسابها (للمحاسبة)، مع اسمها ورقمها
alter table public.payments add column if not exists acct_phone text;
alter table public.payments add column if not exists acct_name text;
alter table public.payments alter column account_id drop not null;
alter table public.payments drop constraint if exists payments_account_id_fkey;
alter table public.payments add constraint payments_account_id_fkey
  foreign key (account_id) references public.accounts(id) on delete set null;

create or replace function public.delete_account(p_token text, p_pass text)
 returns void language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct(p_token);
begin
  if a.pass_hash <> extensions.crypt(coalesce(p_pass,''), a.pass_hash) then raise exception 'E_BAD_LOGIN'; end if;
  update public.payments set acct_phone=a.phone, acct_name=a.mill_name where account_id=a.id;
  delete from public.accounts where id=a.id;  -- الجلسات والفواتير والرسائل تُحذف، والمدفوعات تبقى
end $function$;

create or replace function public.admin_payments(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  return coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
      'mill_name',coalesce(a.mill_name, p.acct_name||' (محذوف)'),'phone',coalesce(a.phone,p.acct_phone))
      order by (p.status='pending') desc, p.created_at desc)
    from public.payments p left join public.accounts a on a.id=p.account_id),'[]'::jsonb);
end $function$;

-- مدفوعة لحساب محذوف لا تُطبَّق على أي اشتراك
create or replace function public._apply_payment(p_pay bigint)
 returns void language plpgsql set search_path to '' as $function$
declare p public.payments; a public.accounts; m int;
begin
  select * into p from public.payments where id=p_pay;
  if p.id is null or p.account_id is null or p.kind<>'monthly' or p.status<>'confirmed' or p.months>0 then return; end if;
  select * into a from public.accounts where id=p.account_id;
  if a.id is null then return; end if;
  m := greatest(1, round(p.amount / greatest(a.monthly_fee,1))::int);
  update public.payments set months=m where id=p.id;
  update public.accounts set paid_until = (greatest(coalesce(paid_until,current_date), current_date) + make_interval(months => m))::date where id=a.id;
end $function$;

-- 3) الاشتراك: ساري حتى نهاية يوم paid_until (UTC)، ثم مهلة 48 ساعة، ثم تتوقف المزامنة
create or replace function public._grace_until(a public.accounts)
returns timestamptz language sql stable set search_path to '' as $$
  select case when a.role='mill' and a.paid_until is not null
    then ((a.paid_until + 1)::timestamp at time zone 'UTC') + interval '48 hours' end
$$;
revoke all on function public._grace_until(public.accounts) from public, anon, authenticated;

create or replace function public._acct_paid(p_token text)
returns public.accounts language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct(p_token); g timestamptz;
begin
  g := public._grace_until(a);
  if g is not null and now() >= g then raise exception 'E_EXPIRED'; end if;
  return a;
end $function$;
revoke all on function public._acct_paid(text) from public, anon, authenticated;

create or replace function public._me_json(a public.accounts)
 returns jsonb language sql set search_path to '' as $function$
  select jsonb_build_object('id',a.id,'phone',a.phone,'mill_name',a.mill_name,'phone2',a.phone2,'role',a.role,'status',a.status,'created_at',a.created_at,
    'setup_fee',a.setup_fee,'monthly_fee',a.monthly_fee,'paid_until',a.paid_until,'grace_until',public._grace_until(a),
    'setup_paid',(select coalesce(sum(p.amount),0) from public.payments p where p.account_id=a.id and p.kind='setup' and p.status='confirmed'))
$function$;

create or replace function public.data_pull(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct_paid(p_token);
begin
  update public.accounts set last_sync=now() where id=a.id;
  return coalesce((select jsonb_object_agg(path,data) from public.docs where account_id=a.id),'{}'::jsonb);
end $function$;

-- 4) حد لحجم بيانات كل حساب: 20000 مستند و50 ميغابايت
create or replace function public.data_push(p_token text, p_ops jsonb)
 returns integer language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct_paid(p_token); op jsonb; n int := 0; nm text;
  v_count int; v_bytes bigint; v_old int;
begin
  if jsonb_typeof(p_ops)<>'array' or jsonb_array_length(p_ops)>500 then raise exception 'E_ARG'; end if;
  select count(*), coalesce(sum(octet_length(data::text)),0) into v_count, v_bytes from public.docs where account_id=a.id;
  for op in select * from jsonb_array_elements(p_ops) loop
    if not public._valid_path(op->>'path') then raise exception 'E_ARG'; end if;
    select octet_length(data::text) into v_old from public.docs where account_id=a.id and path=op->>'path';
    if op ? 'data' and op->'data' <> 'null'::jsonb then
      if jsonb_typeof(op->'data')<>'object' or octet_length((op->'data')::text)>262144 then raise exception 'E_TOO_BIG'; end if;
      v_bytes := v_bytes - coalesce(v_old,0) + octet_length((op->'data')::text);
      if v_old is null then v_count := v_count + 1; end if;
      if v_count > 20000 or v_bytes > 52428800 then raise exception 'E_QUOTA'; end if;
      insert into public.docs(account_id,path,data,updated_at) values (a.id,op->>'path',op->'data',now())
       on conflict (account_id,path) do update set data=excluded.data, updated_at=now();
      if op->>'path'='settings/main' then
        nm := nullif(trim(coalesce(op->'data'->>'name','')),'');
        if nm is not null then update public.accounts set mill_name=nm where id=a.id; end if;
      end if;
    else
      delete from public.docs where account_id=a.id and path=op->>'path';
      if v_old is not null then v_count := v_count - 1; v_bytes := v_bytes - v_old; end if;
    end if;
    n := n+1;
  end loop;
  update public.accounts set last_sync=now() where id=a.id;
  return n;
end $function$;

-- 5) تنظيف الصلاحيات: هذه الدوال لا يحتاجها دور authenticated (التطبيق يستعمل anon + رمز الجلسة)
revoke execute on function public.admin_add_payment(text,uuid,numeric,text,text,text,text,text) from authenticated;
revoke execute on function public.admin_set_sub(text,uuid,date,numeric,numeric) from authenticated;
revoke execute on function public.payment_add(text,numeric,text,text,text,text,text) from authenticated;

commit;
select 'dar security + subscription ok' as result;

-- 6) (أُضيف بعد التنفيذ) هذه الدوال الثلاث كانت متاحة لـ PUBLIC: تُحصر في anon فقط
revoke execute on function public.admin_add_payment(text,uuid,numeric,text,text,text,text,text) from public;
revoke execute on function public.admin_set_sub(text,uuid,date,numeric,numeric) from public;
revoke execute on function public.payment_add(text,numeric,text,text,text,text,text) from public;
grant execute on function public.admin_add_payment(text,uuid,numeric,text,text,text,text,text) to anon;
grant execute on function public.admin_set_sub(text,uuid,date,numeric,numeric) to anon;
grant execute on function public.payment_add(text,numeric,text,text,text,text,text) to anon;
