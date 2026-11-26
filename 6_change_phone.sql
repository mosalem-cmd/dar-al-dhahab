-- 6) تغيير رقم الدخول بواسطة صاحب حساب المطحنة نفسه، بتأكيد كلمة السر (v2.6.2)
-- رقم المشرف لا يتغير هنا لأن صلاحيته مرتبطة بجدول admin_phones.
begin;
create or replace function public.change_phone(p_token text, p_pass text, p_new_phone text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare a public.accounts := public._acct(p_token); ph text := public._digits(p_new_phone);
begin
  if a.role <> 'mill' then raise exception 'E_ADMIN_PHONE'; end if;            -- رقم المشرف مرتبط بصلاحياته فلا يتغير هنا
  if a.pass_hash <> extensions.crypt(coalesce(p_pass,''), a.pass_hash) then raise exception 'E_BAD_LOGIN'; end if;
  if length(ph) < 8 then raise exception 'E_PHONE'; end if;
  if ph = a.phone then return public._me_json(a); end if;
  if exists(select 1 from public.accounts where phone = ph)
     or exists(select 1 from public.admin_phones where phone = ph) then raise exception 'E_PHONE_TAKEN'; end if;
  update public.accounts set phone = ph where id = a.id returning * into a;
  delete from public.sessions where account_id = a.id and token <> p_token;  -- خروج الأجهزة الأخرى
  return public._me_json(a);
exception when unique_violation then raise exception 'E_PHONE_TAKEN';
end $function$;
revoke all on function public.change_phone(text,text,text) from public, authenticated;
grant execute on function public.change_phone(text,text,text) to anon;
commit;

-- التراجع (عند الحاجة فقط):
-- drop function if exists public.change_phone(text,text,text);
