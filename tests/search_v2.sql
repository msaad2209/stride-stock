-- Optional search/index smoke test (Supabase SQL Editor, database owner).
-- Replace the admin UUID. All inserted test rows are rolled back at the end.
begin;
do $$
declare sh uuid; cat uuid; item_id uuid;
begin
  insert into public.shops(name) values('Search benchmark rollback') returning id into sh;
  select id into cat from public.categories where shop_id=sh and active limit 1;
  insert into public.items(shop_id,name,article_no,category_id,default_price) values(sh,'Sparx Benchmark','A101',cat,999) returning id into item_id;
  insert into public.variants(shop_id,item_id,color,size,quantity)
  select sh,item_id,'Black',n::text,1 from generate_series(1,10000) n;
end $$;
select set_config('request.jwt.claim.sub','REPLACE_WITH_ADMIN_USER_UUID',true);
set local role authenticated;
explain (analyze,buffers) select * from public.search_variants('sparx a101 black 9999',null,null,null,'all',50,0,(select id from public.shops where name='Search benchmark rollback'));
select * from public.search_variants('FW000123',null,null,null,'all',50,0,(select id from public.shops where name='Search benchmark rollback'));
select * from public.search_variants('% John''s',null,null,null,'all',50,0,(select id from public.shops where name='Search benchmark rollback'));
rollback;
