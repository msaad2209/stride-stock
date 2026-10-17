-- StrideStock schema contract v3. Run before deploying the v3 frontend.
-- This migration preserves all business data. Run reset_all_data.sql separately only if intended.
create table if not exists public.app_meta (
  key text primary key,
  value text not null
);
insert into public.app_meta(key, value) values ('schema_version', '3')
on conflict (key) do update set value = excluded.value;
alter table public.app_meta enable row level security;
drop policy if exists app_meta_authenticated_read on public.app_meta;
create policy app_meta_authenticated_read on public.app_meta for select to authenticated using (true);
grant select on public.app_meta to authenticated;

-- Remove beta RPC signatures that can make PostgREST resolve the wrong contract.
do $$
declare f record; expected_sell oid; expected_return oid;
begin
  expected_sell := to_regprocedure('public.sell_variant(text,numeric,uuid,uuid)')::oid;
  expected_return := to_regprocedure('public.return_sale(uuid,text,uuid)')::oid;
  for f in select p.oid, p.oid::regprocedure as signature, p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('add_stock','sell_variant','return_sale')
  loop
    if f.proname='add_stock'
       or (f.proname='sell_variant' and f.oid <> coalesce(expected_sell, 0::oid))
       or (f.proname='return_sale' and f.oid <> coalesce(expected_return, 0::oid)) then
      execute 'drop function ' || f.signature;
    end if;
  end loop;
end $$;

create or replace function public.get_schema_version()
returns text language sql stable security invoker set search_path=public
as $$ select value from public.app_meta where key='schema_version' $$;
revoke all on function public.get_schema_version() from public, anon;
grant execute on function public.get_schema_version() to authenticated;

drop function if exists public.batch_label_rows(uuid,uuid);
create function public.batch_label_rows(p_batch_id uuid, p_shop_id uuid)
returns table(
  id uuid, shop_id uuid, item_id uuid, category_id uuid, name text, article_no text,
  category_name text, color text, size text, sku_code text, quantity integer,
  qty_added integer, default_price numeric
)
language plpgsql stable security invoker set search_path=public
as $$
declare sid uuid;
begin
  sid := public.resolve_shop(p_shop_id);
  return query
    select v.id, v.shop_id, v.item_id, i.category_id, i.name, i.article_no, c.name,
           v.color, v.size, v.sku_code, v.quantity, sum(se.qty_added)::integer, i.default_price
    from public.stock_entries se
    join public.variants v on v.id=se.variant_id and v.shop_id=sid
    join public.items i on i.id=v.item_id
    left join public.categories c on c.id=i.category_id
    where se.batch_id=p_batch_id and se.shop_id=sid and se.qty_added>0
    group by v.id, v.shop_id, v.item_id, i.category_id, i.name, i.article_no, c.name,
             v.color, v.size, v.sku_code, v.quantity, i.default_price
    having sum(se.qty_added)>0
    order by i.name, v.color, v.size;
end $$;
revoke all on function public.batch_label_rows(uuid,uuid) from public, anon;
grant execute on function public.batch_label_rows(uuid,uuid) to authenticated;

create or replace function public.check_functions()
returns table(function_name text, "exists" boolean)
language plpgsql stable security definer set search_path=public
as $$
begin
  if not public.is_admin() then
    raise exception 'Permission denied for this shop' using errcode='42501';
  end if;
  return query select expected.name::text, to_regprocedure(expected.signature::text) is not null
  from (values
    ('get_schema_version','public.get_schema_version()'),
    ('check_functions','public.check_functions()'),
    ('check_rls_enabled','public.check_rls_enabled()'),
    ('add_stock_batch','public.add_stock_batch(jsonb,uuid)'),
    ('batch_label_rows','public.batch_label_rows(uuid,uuid)'),
    ('search_variants','public.search_variants(text,uuid,text,text,text,integer,integer,uuid,uuid,text,timestamptz)'),
    ('shop_stats','public.shop_stats(uuid)'),
    ('list_sales','public.list_sales(uuid,timestamptz,timestamptz,text,text,integer,integer,uuid)'),
    ('shop_colors','public.shop_colors(uuid)'),
    ('sell_variant','public.sell_variant(text,numeric,uuid,uuid)'),
    ('return_sale','public.return_sale(uuid,text,uuid)'),
    ('adjust_stock','public.adjust_stock(uuid,integer,text,uuid)')
  ) as expected(name,signature)
  order by expected.name;
end $$;
revoke all on function public.check_functions() from public, anon;
grant execute on function public.check_functions() to authenticated;

create or replace function public.check_rls_enabled()
returns table(table_name text, enabled boolean)
language plpgsql stable security definer set search_path=public
as $$
begin
  if not public.is_admin() then
    raise exception 'Permission denied for this shop' using errcode='42501';
  end if;
  return query
    select c.relname::text, c.relrowsecurity
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('shops','profiles','categories','items','variants','stock_entries','sales','app_meta')
    order by c.relname;
end $$;
revoke all on function public.check_rls_enabled() from public, anon;
grant execute on function public.check_rls_enabled() to authenticated;

notify pgrst, 'reload schema';
