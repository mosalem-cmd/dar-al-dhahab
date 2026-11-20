-- دار الذهب: الأداء مع عدد كبير من المطاحن (نسخة 2.2.0)
-- يُنفَّذ بعد 1_security_subscription.sql. آمن للتكرار.
-- المشكلة: لوحة المشرف كانت تقرأ كل فواتير كل المطاحن في كل مرة، فتتجاوز
-- حد 3 ثوانٍ في Supabase عند حوالي 1000 مطحنة. والهاتف كان ينزّل كل البيانات
-- في كل فتح. الحل: عدّادات جاهزة لكل حساب، ومزامنة بالتغييرات فقط.
begin;

-- 1) عدّادات جاهزة لكل حساب، تُحدَّث تلقائياً مع كل حفظ أو حذف
create table if not exists public.acct_stats(
  account_id uuid primary key references public.accounts(id) on delete cascade,
  docs int not null default 0, bytes bigint not null default 0,
  invoices int not null default 0, customers int not null default 0,
  net numeric not null default 0, grams numeric not null default 0);
alter table public.acct_stats enable row level security;
revoke all on public.acct_stats from anon, authenticated;

create or replace function public._docs_stats()
returns trigger language plpgsql security definer set search_path to '' as $function$
declare
  d_docs int := 0; d_bytes bigint := 0; d_inv int := 0; d_cus int := 0; d_net numeric := 0; d_grams numeric := 0;
  acct uuid := coalesce(new.account_id, old.account_id);
begin
  if tg_op in ('UPDATE','DELETE') then
    d_docs := d_docs - 1; d_bytes := d_bytes - octet_length(old.data::text);
    if old.path like 'invoices/%' then
      d_inv := d_inv - 1; d_grams := d_grams - public._num(old.data->>'grams');
      if jsonb_typeof(old.data->'net')='number' then d_net := d_net - (old.data->>'net')::numeric; end if;
    elsif old.path like 'customers/%' then d_cus := d_cus - 1; end if;
  end if;
  if tg_op in ('INSERT','UPDATE') then
    d_docs := d_docs + 1; d_bytes := d_bytes + octet_length(new.data::text);
    if new.path like 'invoices/%' then
      d_inv := d_inv + 1; d_grams := d_grams + public._num(new.data->>'grams');
      if jsonb_typeof(new.data->'net')='number' then d_net := d_net + (new.data->>'net')::numeric; end if;
    elsif new.path like 'customers/%' then d_cus := d_cus + 1; end if;
    insert into public.acct_stats as s(account_id,docs,bytes,invoices,customers,net,grams)
      values (acct,d_docs,d_bytes,d_inv,d_cus,d_net,d_grams)
      on conflict (account_id) do update set docs=s.docs+excluded.docs, bytes=s.bytes+excluded.bytes,
        invoices=s.invoices+excluded.invoices, customers=s.customers+excluded.customers,
        net=s.net+excluded.net, grams=s.grams+excluded.grams;
  else
    -- عند حذف الحساب نفسه يكون صف العدّاد قد حُذف أيضاً، فلا نُنشئه من جديد
    update public.acct_stats set docs=docs+d_docs, bytes=bytes+d_bytes, invoices=invoices+d_inv,
      customers=customers+d_cus, net=net+d_net, grams=grams+d_grams where account_id=acct;
  end if;
  return null;
end $function$;
revoke all on function public._docs_stats() from public, anon, authenticated;

drop trigger if exists docs_stats on public.docs;
create trigger docs_stats after insert or update or delete on public.docs
  for each row execute function public._docs_stats();

-- حساب العدّادات للبيانات الموجودة الآن
insert into public.acct_stats(account_id,docs,bytes,invoices,customers,net,grams)
select d.account_id, count(*), sum(octet_length(d.data::text)),
  count(*) filter (where d.path like 'invoices/%'), count(*) filter (where d.path like 'customers/%'),
  coalesce(sum((d.data->>'net')::numeric) filter (where d.path like 'invoices/%' and jsonb_typeof(d.data->'net')='number'),0),
  coalesce(sum(public._num(d.data->>'grams')) filter (where d.path like 'invoices/%'),0)
from public.docs d group by d.account_id
on conflict (account_id) do update set docs=excluded.docs, bytes=excluded.bytes, invoices=excluded.invoices,
  customers=excluded.customers, net=excluded.net, grams=excluded.grams;

-- 2) لوحة المشرف تقرأ العدّادات بدل كل الفواتير
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
    'invoices',(select coalesce(sum(s.invoices),0) from public.acct_stats s join public.accounts a on a.id=s.account_id where a.role='mill'),
    'grams',(select coalesce(sum(s.grams),0) from public.acct_stats s join public.accounts a on a.id=s.account_id where a.role='mill'),
    'sub_expired',(select count(*) from public.accounts where role='mill' and paid_until is not null and paid_until<current_date),
    'sub_soon',(select count(*) from public.accounts where role='mill' and paid_until is not null and paid_until>=current_date and paid_until<=current_date+7),
    'sub_none',(select count(*) from public.accounts where role='mill' and paid_until is null),
    'setup_due',(select count(*) from public.accounts a where a.role='mill' and a.setup_fee > (select coalesce(sum(p.amount),0) from public.payments p where p.account_id=a.id and p.kind='setup' and p.status='confirmed')));
end $function$;

create or replace function public.admin_accounts(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  return coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
    select jsonb_build_object('id',a.id,'phone',a.phone,'phone2',a.phone2,'mill_name',a.mill_name,'role',a.role,'status',a.status,'code_used',a.code_used,
      'created_at',a.created_at,'last_login',a.last_login,'last_sync',a.last_sync,
      'setup_fee',a.setup_fee,'monthly_fee',a.monthly_fee,'paid_until',a.paid_until,
      'setup_paid',coalesce(p.setup_paid,0),
      'invoices',coalesce(s.invoices,0),'customers',coalesce(s.customers,0),'net',coalesce(s.net,0),
      'msgs_open',coalesce(m.open,0),'paid',coalesce(p.paid,0),'pay_pending',coalesce(p.pending,0)) x
    from public.accounts a
    left join public.acct_stats s on s.account_id=a.id
    left join (select account_id, sum(amount) filter (where kind='setup' and status='confirmed') setup_paid,
                 sum(amount) filter (where status='confirmed') paid, count(*) filter (where status='pending') pending
               from public.payments group by account_id) p on p.account_id=a.id
    left join (select account_id, count(*) open from public.messages where status='open' group by account_id) m on m.account_id=a.id) q),'[]'::jsonb);
end $function$;

-- 3) الحد الأقصى للبيانات من العدّادات (بدل حساب حجم كل الفواتير في كل حفظ)
create or replace function public.data_push(p_token text, p_ops jsonb)
 returns integer language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct_paid(p_token); op jsonb; n int := 0; nm text;
  v_count int; v_bytes bigint; v_old int;
begin
  if jsonb_typeof(p_ops)<>'array' or jsonb_array_length(p_ops)>500 then raise exception 'E_ARG'; end if;
  select coalesce(max(docs),0), coalesce(max(bytes),0) into v_count, v_bytes from public.acct_stats where account_id=a.id;
  for op in select * from jsonb_array_elements(p_ops) loop
    if not public._valid_path(op->>'path') then raise exception 'E_ARG'; end if;
    v_old := null;
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

-- 4) مزامنة بالتغييرات فقط: الهاتف يرسل وقت آخر مزامنة، فيستلم ما تغيّر بعدها
-- مع قائمة المسارات الموجودة (ليحذف ما حُذف من جهاز آخر). أول مرة: كل شيء.
create index if not exists docs_account_updated_idx on public.docs(account_id, updated_at);
create or replace function public.data_sync(p_token text, p_since timestamptz default null)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct_paid(p_token); v_now timestamptz := now();
begin
  update public.accounts set last_sync=v_now where id=a.id;
  return jsonb_build_object(
    'now', v_now - interval '30 seconds',
    'full', p_since is null,
    'docs', coalesce((select jsonb_object_agg(path,data) from public.docs where account_id=a.id and (p_since is null or updated_at >= p_since)),'{}'::jsonb),
    'paths', case when p_since is null then null else coalesce((select jsonb_agg(path) from public.docs where account_id=a.id),'[]'::jsonb) end);
end $function$;
revoke all on function public.data_sync(text,timestamptz) from public, authenticated;
grant execute on function public.data_sync(text,timestamptz) to anon;

commit;
select 'dar scale ok' as result;

-- 5) (أُضيف بعد التنفيذ) الأرقام العربية ١٢٣ والفاصلة العشرية ٫ تُحسب صحيحة في الإحصاءات
create or replace function public._num(p text)
returns numeric language sql immutable set search_path to '' as $$
  with s as (select regexp_replace(translate(coalesce(p,''),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٫،','01234567890123456789..'),'[^0-9.]','','g') v)
  select case when v ~ '^[0-9]+(\.[0-9]+)?$' then v::numeric else 0 end from s
$$;
revoke all on function public._num(text) from public, anon, authenticated;
update public.acct_stats s set grams = coalesce((select sum(public._num(d.data->>'grams')) from public.docs d where d.account_id=s.account_id and d.path like 'invoices/%'),0);
