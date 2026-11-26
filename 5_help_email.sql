-- 5) إشعار بريدي للمشرف عند كل طلب مساعدة (Resend). المفتاح في Vault فقط.
-- المفتاح يضعه صاحب التطبيق بنفسه في SQL Editor (لا يُكتب هنا ولا في أي مكان في المستودع):
--   select vault.create_secret('<API key>', 'resend_api_key');
-- بلا مفتاح: لا يُرسل شيء ولا يتعطل حفظ الطلب.
begin;
create extension if not exists pg_net;   -- طلبات HTTP غير متزامنة: لا تؤخر حفظ الطلب

create or replace function public._notify_help_email()
 returns trigger language plpgsql security definer set search_path to '' as $function$
declare k text; a public.accounts;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if k is null then return new; end if;                        -- بلا مفتاح: لا إرسال
  select * into a from public.accounts where id = new.account_id;
  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body    := jsonb_build_object(
      'from',    'Dar al-Dhahab <onboarding@resend.dev>',
      'to',      jsonb_build_array('daraldhahab.support@gmail.com'),
      'subject', 'طلب مساعدة: ' || coalesce(a.mill_name, '') || ' · ' || coalesce(new.problem_id, 'نص حر'),
      'text',    concat_ws(E'\n',
                   'المطحنة: '   || coalesce(a.mill_name, ''),
                   'الهاتف: '    || coalesce(a.phone, ''),
                   'المشكلة: '   || coalesce(new.problem_id, 'نص حر'),
                   'النص: '      || new.body,
                   'الإصدار: '   || coalesce(new.meta->>'appVersion', ''),
                   'رقم الطلب: ' || new.id,
                   'الرد من لوحة المشرف ← الشكاوى والملاحظات.')));
  return new;
exception when others then
  return new;                                                   -- أي خطأ في الإشعار لا يمنع حفظ الطلب
end $function$;
revoke all on function public._notify_help_email() from public, anon, authenticated;

create trigger help_email_notify after insert on public.messages
  for each row when (new.kind = 'help') execute function public._notify_help_email();
commit;

-- التراجع (عند الحاجة فقط):
-- drop trigger if exists help_email_notify on public.messages;
-- drop function if exists public._notify_help_email();
