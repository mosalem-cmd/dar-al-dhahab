-- 4) طلبات المساعدة من زر «المساعدة» (المرحلة 2، v2.6.0)
-- يعيد استعمال جدول الرسائل: نوع جديد «help»، والرد يصل لصاحب المطحنة في «الشكاوى والملاحظات».
begin;

-- أ) نوع رسالة جديد «help» + حقلان اختياريان: المشكلة المختارة وسياق التطبيق
alter table public.messages drop constraint messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind = any (array['complaint','note','suggestion','help']));
alter table public.messages add column if not exists problem_id text;   -- مثل 'forgot' أو null للنص الحر
alter table public.messages add column if not exists meta jsonb;        -- {lang, appVersion, view}

-- ب) الإرسال: للحسابات المسجّلة فقط، وحد أقصى 5 طلبات مساعدة في الساعة لكل حساب
create or replace function public.help_request(p_token text, p_problem text, p_text text, p_meta jsonb)
 returns bigint language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct(p_token); i bigint; n int;
begin
  if coalesce(trim(p_text),'')='' and coalesce(p_problem,'')='' then raise exception 'E_ARG'; end if;
  if coalesce(p_problem,'')<>'' and p_problem !~ '^[A-Za-z]{1,20}$' then raise exception 'E_ARG'; end if;
  select count(*) into n from public.messages
   where account_id=a.id and kind='help' and created_at > now() - interval '1 hour';
  if n >= 5 then raise exception 'E_RATE'; end if;
  insert into public.messages(account_id, kind, subject, body, problem_id, meta)
  values (a.id, 'help', left(coalesce(p_problem,''),20), left(coalesce(nullif(trim(p_text),''),'—'),2000),
          nullif(p_problem,''),
          jsonb_build_object('lang', left(coalesce(p_meta->>'lang',''),5),
                             'appVersion', left(coalesce(p_meta->>'appVersion',''),20),
                             'view', left(coalesce(p_meta->>'view',''),20)))
  returning id into i;
  return i;
end $function$;
revoke all on function public.help_request(text,text,text,jsonb) from public, authenticated;
grant execute on function public.help_request(text,text,text,jsonb) to anon;

-- ج) للمشرف: عدد طلبات المساعدة المفتوحة وأكثر المشاكل طلبًا في آخر 90 يومًا
create or replace function public.admin_help_stats(p_token text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare ad public.accounts := public._admin(p_token);
begin
  return jsonb_build_object(
    'open', (select count(*) from public.messages where kind='help' and status='open'),
    'top',  coalesce((select jsonb_agg(jsonb_build_object('problem', coalesce(problem_id,'free'), 'n', n) order by n desc)
                      from (select problem_id, count(*) n from public.messages
                            where kind='help' and created_at > now() - interval '90 days'
                            group by problem_id) s), '[]'::jsonb));
end $function$;
revoke all on function public.admin_help_stats(text) from public, authenticated;
grant execute on function public.admin_help_stats(text) to anon;

commit;

-- التراجع (عند الحاجة فقط):
-- begin;
-- drop function if exists public.help_request(text,text,text,jsonb);
-- drop function if exists public.admin_help_stats(text);
-- update public.messages set kind='complaint' where kind='help';
-- alter table public.messages drop constraint messages_kind_check;
-- alter table public.messages add constraint messages_kind_check check (kind = any (array['complaint','note','suggestion']));
-- alter table public.messages drop column if exists problem_id, drop column if exists meta;
-- commit;
