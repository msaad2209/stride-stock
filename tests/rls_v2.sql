-- Shop isolation check for Supabase SQL Editor (run as database owner).
-- Replace both UUID placeholders from public.profiles / public.shops before running.
-- This script changes only the current transaction and rolls back.
begin;
select set_config('request.jwt.claim.sub','REPLACE_WITH_SHOP_2_USER_UUID',true);
set local role authenticated;
do $$
declare other_shop uuid := 'REPLACE_WITH_SHOP_1_UUID'::uuid; n bigint;
begin
  select count(*) into n from public.variants where shop_id=other_shop;
  if n<>0 then raise exception 'FAIL: Second shop user can read first shop variants (% rows)',n; end if;
  begin
    perform public.resolve_shop(other_shop);
    raise exception 'FAIL: shop user was allowed to select another shop';
  exception when insufficient_privilege then
    raise notice 'PASS: cross-shop RPC scope rejected';
  end;
  begin
    update public.variants set quantity=quantity+1 where shop_id=other_shop;
    raise exception 'FAIL: direct quantity update should be denied';
  exception when insufficient_privilege then
    raise notice 'PASS: direct quantity update denied; use stock RPC';
  end;
  raise notice 'PASS: Second shop cannot read first shop variant rows';
end $$;
rollback;
