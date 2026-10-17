-- DESTRUCTIVE: removes all shop inventory, sales, shops, and shop-user accounts.
-- set confirm to 'DELETE EVERYTHING' by changing the variable in the DO block below.
-- Keep the admin signed into a separate browser session before running this script.
do $$
declare
  confirm text := '';
  before_sales bigint; before_entries bigint; before_variants bigint;
  before_items bigint; before_categories bigint; before_shops bigint; before_profiles bigint;
  after_sales bigint; after_entries bigint; after_variants bigint;
  after_items bigint; after_categories bigint; after_shops bigint; after_profiles bigint;
  sequence_row record;
begin
  if confirm <> 'DELETE EVERYTHING' then
    raise exception 'Safety stop: edit confirm to DELETE EVERYTHING only when you intend to permanently erase all shop data';
  end if;

  select count(*) into before_sales from public.sales;
  select count(*) into before_entries from public.stock_entries;
  select count(*) into before_variants from public.variants;
  select count(*) into before_items from public.items;
  select count(*) into before_categories from public.categories;
  select count(*) into before_shops from public.shops;
  select count(*) into before_profiles from public.profiles where role='shop';
  raise notice 'Before reset: sales %, stock entries %, variants %, items %, categories %, shops %, shop profiles %',
    before_sales,before_entries,before_variants,before_items,before_categories,before_shops,before_profiles;

  delete from public.sales;
  delete from public.stock_entries;
  delete from public.variants;
  delete from public.items;
  delete from public.categories;
  delete from auth.users u using public.profiles p where p.user_id=u.id and p.role='shop';
  delete from public.profiles where role='shop';
  delete from public.shops;

  perform setval('public.sku_sequence', 1, false);
  -- Reset any additional public sequence and start the barcode sequence at FW000001.
  for sequence_row in
    select c.oid::regclass as sequence_name
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='S' and n.nspname='public' and c.relname<>'sku_sequence'
  loop
    perform setval(sequence_row.sequence_name, 1, false);
  end loop;

  select count(*) into after_sales from public.sales;
  select count(*) into after_entries from public.stock_entries;
  select count(*) into after_variants from public.variants;
  select count(*) into after_items from public.items;
  select count(*) into after_categories from public.categories;
  select count(*) into after_shops from public.shops;
  select count(*) into after_profiles from public.profiles where role='shop';
  raise notice 'After reset: sales %, stock entries %, variants %, items %, categories %, shops %, shop profiles %',
    after_sales,after_entries,after_variants,after_items,after_categories,after_shops,after_profiles;
end $$;
