-- 7أ) استعادة كلمة السر، المرحلة أ: الطلب فقط.
-- صاحب الحساب يكتب كلمة سره الجديدة بنفسه؛ تُخزَّن بصمتها (bf) في طلب ينتظر موافقة المشرف.
-- لا يتغير أي حساب هنا: التفعيل في المرحلة ب/ج بعد موافقة المشرف.
begin;

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
commit;

-- التراجع (عند الحاجة فقط):
-- drop function if exists public.reset_request(text, text);
-- drop table if exists public.reset_requests;
