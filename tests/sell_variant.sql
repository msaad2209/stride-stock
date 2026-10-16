-- Run in the Supabase SQL Editor after 001_init.sql. Everything is rolled back.
begin;
do $$
declare sh uuid; cat uuid; item_id uuid; variant_id uuid; code text;
begin
  insert into public.shops(name) values ('SQL safety test') returning id into sh;
  insert into public.categories(shop_id,name) values(sh,'SQL safety test') returning id into cat;
  insert into public.items(shop_id,name,article_no,category_id,default_price) values(sh,'SQL safety test','SQL-NEGATIVE-TEST',cat,100) returning id into item_id;
  insert into public.variants(shop_id,item_id,color,size,quantity) values(sh,item_id,'Black','7',0) returning id,sku_code into variant_id,code;
  begin
    perform public.sell_variant(code,100);
    raise exception 'FAIL: sell_variant accepted a zero-stock sale';
  exception when others then
    if sqlerrm='FAIL: sell_variant accepted a zero-stock sale' then raise; end if;
  end;
  if (select quantity from public.variants where id=variant_id) <> 0 then
    raise exception 'FAIL: quantity changed after rejected sale';
  end if;
  raise notice 'PASS: zero-stock sale rejected and quantity remained zero';
end $$;
rollback;
