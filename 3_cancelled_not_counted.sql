-- دار الذهب 2.3.0 (اختياري، لم يُنفَّذ بعد): الفواتير الملغاة لا تدخل في أرقام لوحة المشرف
begin;
create or replace function public._docs_stats()
returns trigger language plpgsql security definer set search_path to '' as $function$
declare
  d_docs int := 0; d_bytes bigint := 0; d_inv int := 0; d_cus int := 0; d_net numeric := 0; d_grams numeric := 0;
  acct uuid := coalesce(new.account_id, old.account_id);
begin
  if tg_op in ('UPDATE','DELETE') then
    d_docs := d_docs - 1; d_bytes := d_bytes - octet_length(old.data::text);
    if old.path like 'invoices/%' and not (old.data ? 'cancelled') then
      d_inv := d_inv - 1; d_grams := d_grams - public._num(old.data->>'grams');
      if jsonb_typeof(old.data->'net')='number' then d_net := d_net - (old.data->>'net')::numeric; end if;
    elsif old.path like 'customers/%' then d_cus := d_cus - 1; end if;
  end if;
  if tg_op in ('INSERT','UPDATE') then
    d_docs := d_docs + 1; d_bytes := d_bytes + octet_length(new.data::text);
    if new.path like 'invoices/%' and not (new.data ? 'cancelled') then
      d_inv := d_inv + 1; d_grams := d_grams + public._num(new.data->>'grams');
      if jsonb_typeof(new.data->'net')='number' then d_net := d_net + (new.data->>'net')::numeric; end if;
    elsif new.path like 'customers/%' then d_cus := d_cus + 1; end if;
    insert into public.acct_stats as s(account_id,docs,bytes,invoices,customers,net,grams)
      values (acct,d_docs,d_bytes,d_inv,d_cus,d_net,d_grams)
      on conflict (account_id) do update set docs=s.docs+excluded.docs, bytes=s.bytes+excluded.bytes,
        invoices=s.invoices+excluded.invoices, customers=s.customers+excluded.customers,
        net=s.net+excluded.net, grams=s.grams+excluded.grams;
  else
    update public.acct_stats set docs=docs+d_docs, bytes=bytes+d_bytes, invoices=invoices+d_inv,
      customers=customers+d_cus, net=net+d_net, grams=grams+d_grams where account_id=acct;
  end if;
  return null;
end $function$;
update public.acct_stats s set
  invoices=(select count(*) from public.docs d where d.account_id=s.account_id and d.path like 'invoices/%' and not (d.data ? 'cancelled')),
  net=coalesce((select sum((d.data->>'net')::numeric) from public.docs d where d.account_id=s.account_id and d.path like 'invoices/%' and not (d.data ? 'cancelled') and jsonb_typeof(d.data->'net')='number'),0),
  grams=coalesce((select sum(public._num(d.data->>'grams')) from public.docs d where d.account_id=s.account_id and d.path like 'invoices/%' and not (d.data ? 'cancelled')),0);
commit;
select 'dar cancelled stats ok' as result;
