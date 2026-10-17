-- StrideStock v2 additive upgrade. Take an export before running this on live data.
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;

alter table public.variants add column if not exists search_text text not null default '';
alter table public.variants add column if not exists size_system text not null default 'UK / IND';
alter table public.stock_entries add column if not exists batch_id uuid;
alter table public.sales add column if not exists client_ref uuid;
alter table public.sales add column if not exists return_reason text;
alter table public.variants alter column sku_code set default ('FW'||to_char(nextval('public.sku_sequence'),'FM000000'));
create unique index if not exists sales_client_ref_uidx on public.sales(client_ref) where client_ref is not null;
create index if not exists variants_search_text_trgm_idx on public.variants using gin (search_text extensions.gin_trgm_ops);
create index if not exists variants_shop_sku_code_idx on public.variants(shop_id,sku_code);
create index if not exists variants_shop_quantity_idx on public.variants(shop_id,quantity);
create index if not exists variants_shop_item_idx on public.variants(shop_id,item_id);
create index if not exists sales_shop_sold_at_desc_idx on public.sales(shop_id,sold_at desc);
create index if not exists sales_shop_status_sold_at_idx on public.sales(shop_id,status,sold_at desc);
create index if not exists stock_entries_shop_created_desc_idx on public.stock_entries(shop_id,created_at desc);
create index if not exists stock_entries_batch_id_idx on public.stock_entries(batch_id);
create index if not exists items_shop_article_lower_idx on public.items(shop_id,lower(article_no));

create table if not exists public.profiles(
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check(role in ('admin','shop')),
  shop_id uuid references public.shops(id),
  active boolean not null default true,
  display_name text,
  created_at timestamptz not null default now(),
  constraint profile_shop_role_check check ((role='shop' and shop_id is not null) or role='admin')
);
alter table public.profiles enable row level security;

-- ADMIN PROFILE SETUP: replace this address with the existing Supabase Auth admin email,
-- then run this migration. It links the existing user without changing password or data.
do $$ declare admin_email text := 'msaad2209bk2@gmail.com'; admin_id uuid; begin
  select id into admin_id from auth.users where lower(email)=lower(admin_email) limit 1;
  if admin_id is null then raise exception 'No Supabase Auth user found for admin email %', admin_email; end if;
  insert into public.profiles(user_id,role,shop_id,active,display_name)
  values(admin_id,'admin',null,true,split_part(admin_email,'@',1))
  on conflict(user_id) do update set role='admin',shop_id=null,active=true;
end $$;

create or replace function public.auth_role() returns text language sql stable security definer set search_path=public as $$
 select role from public.profiles where user_id=auth.uid() and active=true
$$;
create or replace function public.auth_shop_id() returns uuid language sql stable security definer set search_path=public as $$
 select shop_id from public.profiles where user_id=auth.uid() and active=true and role='shop'
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where user_id=auth.uid() and active=true and role='admin')
$$;
revoke all on function public.auth_role(),public.auth_shop_id(),public.is_admin() from public;
grant execute on function public.auth_role(),public.auth_shop_id(),public.is_admin() to authenticated;

create or replace function public.seed_shop_categories(p_shop_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  insert into public.categories(shop_id,name) select p_shop_id,n from (values
   ('Fancy - Ladies'),('Fancy - Kids'),('Slipper - Gents'),('Slipper - Ladies'),('Slipper - Gkids'),('Slipper - LKids'),
   ('Shoes - Gents'),('Shoes - Ladies'),('Shoes - Gkids'),('Shoes - LKids'),('Sandal - Ladies'),('Sandal - Gents'),('Sandal - Gkids'),('Sandal - LKids')
  ) v(n) on conflict(shop_id,name) do update set active=true;
end $$;
create or replace function public.on_shop_created_seed_categories() returns trigger language plpgsql security definer set search_path=public as $$
begin perform public.seed_shop_categories(new.id); return new; end $$;
drop trigger if exists shops_seed_categories on public.shops;
create trigger shops_seed_categories after insert on public.shops for each row execute function public.on_shop_created_seed_categories();
do $$ declare s record; begin
 for s in select id from public.shops loop perform public.seed_shop_categories(s.id); end loop;
end $$;
update public.categories set active=false where name in ('Fancy','Gents PU','Ladies PU','Kids PU','Shoes','Sandals','Slippers','Sports Shoes');

create or replace function public.enforce_shop_references() returns trigger language plpgsql security definer set search_path=public as $$
declare ref_shop uuid; begin
 if tg_table_name='items' then
  perform pg_advisory_xact_lock(hashtextextended(new.shop_id::text||lower(trim(new.article_no)),0));
  if exists(select 1 from public.items i where i.shop_id=new.shop_id and lower(i.article_no)=lower(trim(new.article_no)) and i.id is distinct from new.id) then raise exception 'Article number already exists in this shop (case-insensitive)'; end if;
  if new.category_id is not null and not exists(select 1 from public.categories where id=new.category_id and shop_id=new.shop_id) then raise exception 'Category must belong to the same shop'; end if;
 elsif tg_table_name='variants' then
  if not exists(select 1 from public.items where id=new.item_id and shop_id=new.shop_id) then raise exception 'Item must belong to the same shop'; end if;
 elsif tg_table_name in ('sales','stock_entries') then
  if not exists(select 1 from public.variants where id=new.variant_id and shop_id=new.shop_id) then raise exception 'Variant must belong to the same shop'; end if;
 end if;
 return new;
end $$;
revoke all on function public.enforce_shop_references() from public,anon,authenticated;
drop trigger if exists items_shop_reference_check on public.items;
create trigger items_shop_reference_check before insert or update of shop_id,category_id on public.items for each row execute function public.enforce_shop_references();
drop trigger if exists variants_shop_reference_check on public.variants;
create trigger variants_shop_reference_check before insert or update of shop_id,item_id on public.variants for each row execute function public.enforce_shop_references();
drop trigger if exists sales_shop_reference_check on public.sales;
create trigger sales_shop_reference_check before insert or update of shop_id,variant_id on public.sales for each row execute function public.enforce_shop_references();
drop trigger if exists stock_entries_shop_reference_check on public.stock_entries;
create trigger stock_entries_shop_reference_check before insert or update of shop_id,variant_id on public.stock_entries for each row execute function public.enforce_shop_references();

create or replace function public.variant_search_text(p_variant_id uuid) returns text language sql stable security definer set search_path=public as $$
 select lower(concat_ws(' ',i.name,i.article_no,v.color,v.size,v.sku_code,c.name))
 from public.variants v join public.items i on i.id=v.item_id left join public.categories c on c.id=i.category_id where v.id=p_variant_id
$$;
revoke all on function public.variant_search_text(uuid),public.seed_shop_categories(uuid),public.on_shop_created_seed_categories() from public,anon,authenticated;
create or replace function public.refresh_variant_search_text() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_table_name='variants' then
   update public.variants v set search_text=public.variant_search_text(v.id) where v.id=coalesce(new.id,old.id);
 elsif tg_table_name='items' then
   update public.variants v set search_text=public.variant_search_text(v.id) where v.item_id=coalesce(new.id,old.id);
 elsif tg_table_name='categories' then
   update public.variants v set search_text=public.variant_search_text(v.id) from public.items i where v.item_id=i.id and i.category_id=coalesce(new.id,old.id);
 end if;
 return new;
end $$;
drop trigger if exists variants_refresh_search on public.variants;
create trigger variants_refresh_search after insert or update of item_id,color,size,sku_code on public.variants for each row execute function public.refresh_variant_search_text();
drop trigger if exists items_refresh_search on public.items;
create trigger items_refresh_search after update of name,article_no,category_id on public.items for each row execute function public.refresh_variant_search_text();
drop trigger if exists categories_refresh_search on public.categories;
create trigger categories_refresh_search after update of name on public.categories for each row execute function public.refresh_variant_search_text();
update public.variants set search_text=public.variant_search_text(id);

-- Replace permissive beta policies with profile-aware shop isolation.
do $$ declare t text; p record; begin
 foreach t in array array['shops','categories','items','variants','stock_entries','sales','profiles'] loop
  for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
   execute format('drop policy %I on public.%I',p.policyname,t);
  end loop;
 end loop;
end $$;
create policy profile_self_read on public.profiles for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy profile_admin_manage on public.profiles for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy shops_profile_read on public.shops for select to authenticated using(public.is_admin() or id=public.auth_shop_id());
create policy shops_admin_write on public.shops for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy categories_shop_access on public.categories for all to authenticated using(public.is_admin() or shop_id=public.auth_shop_id()) with check((public.is_admin() and shop_id is not null) or shop_id=public.auth_shop_id());
create policy items_shop_access on public.items for all to authenticated using(public.is_admin() or shop_id=public.auth_shop_id()) with check((public.is_admin() and shop_id is not null) or shop_id=public.auth_shop_id());
create policy variants_shop_access on public.variants for all to authenticated using(public.is_admin() or shop_id=public.auth_shop_id()) with check((public.is_admin() and shop_id is not null) or shop_id=public.auth_shop_id());
create policy stock_entries_shop_access on public.stock_entries for all to authenticated using(public.is_admin() or shop_id=public.auth_shop_id()) with check((public.is_admin() and shop_id is not null) or shop_id=public.auth_shop_id());
create policy sales_shop_access on public.sales for all to authenticated using(public.is_admin() or shop_id=public.auth_shop_id()) with check((public.is_admin() and shop_id is not null) or shop_id=public.auth_shop_id());

create or replace function public.resolve_shop(p_shop_id uuid default null) returns uuid language plpgsql stable security invoker set search_path=public as $$
declare sid uuid; begin
 if public.is_admin() then sid:=p_shop_id; if sid is null then raise exception 'Admin must select a shop'; end if;
 else sid:=public.auth_shop_id(); if sid is null or (p_shop_id is not null and p_shop_id<>sid) then raise exception 'Forbidden: shop access denied' using errcode='42501'; end if;
 end if; return sid;
end $$;

drop function if exists public.sell_variant(text,numeric);
create or replace function public.sell_variant(p_sku_code text,p_sold_price numeric,p_client_ref uuid default null,p_shop_id uuid default null) returns public.sales language plpgsql security definer set search_path=public as $$
declare sid uuid; v public.variants; i public.items; s public.sales; begin
 sid:=public.resolve_shop(p_shop_id); if p_sold_price is null or p_sold_price<0 then raise exception 'Invalid price'; end if;
 if p_client_ref is not null then perform pg_advisory_xact_lock(hashtextextended(p_client_ref::text,0)); end if;
 if p_client_ref is not null then select * into s from public.sales where client_ref=p_client_ref and shop_id=sid; if found then return s; end if; end if;
 update public.variants set quantity=quantity-1 where sku_code=upper(trim(p_sku_code)) and shop_id=sid and active and quantity>0 returning * into v;
 if not found then if exists(select 1 from public.variants where sku_code=upper(trim(p_sku_code)) and shop_id=sid) then raise exception 'Out of stock, cannot sell'; else raise exception 'Item not found in this shop'; end if; end if;
 select * into i from public.items where id=v.item_id;
 insert into public.sales(shop_id,variant_id,sku_code,listed_price,sold_price,client_ref) values(sid,v.id,v.sku_code,i.default_price,p_sold_price,p_client_ref) returning * into s; return s;
end $$;
drop function if exists public.return_sale(uuid);
create or replace function public.return_sale(p_sale_id uuid,p_reason text default null,p_shop_id uuid default null) returns public.sales language plpgsql security definer set search_path=public as $$
declare sid uuid; s public.sales; begin sid:=public.resolve_shop(p_shop_id);
 select * into s from public.sales where id=p_sale_id and shop_id=sid for update;
 if not found then raise exception 'Sale not found in this shop'; end if;
 if s.status='returned' then raise exception 'Sale already returned'; end if;
 update public.sales set status='returned',returned_at=now(),return_reason=nullif(trim(p_reason),'') where id=s.id returning * into s;
 update public.variants set quantity=quantity+1 where id=s.variant_id and shop_id=sid;
 insert into public.stock_entries(shop_id,variant_id,qty_added,note) values(sid,s.variant_id,1,'Return of sale '||s.id::text);
 return s;
end $$;
drop function if exists public.add_stock(uuid,uuid,text,text,integer,text);
create or replace function public.add_stock_batch(p_payload jsonb,p_shop_id uuid default null) returns table(batch_id uuid,variant_id uuid,sku_code text,color text,size text,quantity integer,item_name text,article_no text,default_price numeric) language plpgsql security definer set search_path=public as $$
declare sid uuid; b uuid:=gen_random_uuid(); payload jsonb; iid uuid; cid uuid; variant_row public.variants; qty integer; begin
 sid:=public.resolve_shop(p_shop_id);
 if jsonb_typeof(p_payload)<>'object' or jsonb_typeof(p_payload->'variants')<>'array' or jsonb_array_length(p_payload->'variants')=0 then raise exception 'Stock batch must include variants'; end if;
 if coalesce(trim(p_payload->>'name'),'')='' or coalesce(trim(p_payload->>'article_no'),'')='' then raise exception 'Item name and article number are required'; end if;
 cid:=(p_payload->>'category_id')::uuid;
 if not exists(select 1 from public.categories where id=cid and shop_id=sid and active) then raise exception 'Choose an active category in this shop'; end if;
 perform pg_advisory_xact_lock(hashtextextended(sid::text||lower(trim(p_payload->>'article_no')),0));
 select id into iid from public.items where shop_id=sid and lower(article_no)=lower(trim(p_payload->>'article_no')) for update;
 if found then update public.items set name=trim(p_payload->>'name'),category_id=cid,default_price=(p_payload->>'default_price')::numeric,cost_price=nullif(p_payload->>'cost_price','')::numeric where id=iid;
 else insert into public.items(shop_id,name,article_no,category_id,default_price,cost_price) values(sid,trim(p_payload->>'name'),trim(p_payload->>'article_no'),cid,(p_payload->>'default_price')::numeric,nullif(p_payload->>'cost_price','')::numeric) returning id into iid; end if;
 for payload in select value from jsonb_array_elements(p_payload->'variants') loop
  qty:=(payload->>'quantity')::integer; if qty<1 then raise exception 'Every variant quantity must be at least one'; end if;
  perform pg_advisory_xact_lock(hashtextextended(iid::text||lower(trim(payload->>'color'))||trim(payload->>'size'),0));
  select * into variant_row from public.variants va where va.item_id=iid and lower(va.color)=lower(trim(payload->>'color')) and va.size=trim(payload->>'size') for update;
  if found then update public.variants set quantity=quantity+qty,size_system=coalesce(nullif(trim(p_payload->>'size_system'),''),'UK / IND') where id=variant_row.id returning * into variant_row;
  else insert into public.variants(shop_id,item_id,color,size,size_system,quantity) values(sid,iid,trim(payload->>'color'),trim(payload->>'size'),coalesce(nullif(trim(p_payload->>'size_system'),''),'UK / IND'),qty) returning * into variant_row; end if;
  insert into public.stock_entries(shop_id,variant_id,qty_added,note,batch_id) values(sid,variant_row.id,qty,'Incoming stock batch',b);
 end loop;
 return query select b,va.id,va.sku_code,va.color,va.size,va.quantity,it.name,it.article_no,it.default_price from public.variants va join public.items it on it.id=va.item_id where va.shop_id=sid and va.id in (select se.variant_id from public.stock_entries se where se.batch_id=b);
end $$;
drop function if exists public.adjust_stock(uuid,integer,text);
create or replace function public.adjust_stock(p_variant_id uuid,p_delta integer,p_note text,p_shop_id uuid default null) returns public.variants language plpgsql security definer set search_path=public as $$
declare sid uuid; variant_row public.variants; begin
 sid:=public.resolve_shop(p_shop_id);
 if trim(coalesce(p_note,''))='' or p_delta=0 then raise exception 'Reason and non-zero adjustment required'; end if;
 update public.variants set quantity=quantity+p_delta where id=p_variant_id and shop_id=sid and quantity+p_delta>=0 returning * into variant_row;
 if not found then raise exception 'Adjustment would make stock negative or variant is not in this shop'; end if;
 insert into public.stock_entries(shop_id,variant_id,qty_added,note) values(sid,variant_row.id,p_delta,trim(p_note)); return variant_row;
end $$;
drop function if exists public.search_variants(text,uuid,text,text,text,integer,integer,uuid);
drop function if exists public.search_variants(text,uuid,text,text,text,integer,integer,uuid,uuid);
drop function if exists public.search_variants(text,uuid,text,text,text,integer,integer,uuid,uuid,text);
drop function if exists public.search_variants(text,uuid,text,text,text,integer,integer,uuid,uuid,text,timestamptz);
create or replace function public.search_variants(p_q text default '',p_category uuid default null,p_size text default null,p_color text default null,p_stock text default 'all',p_limit integer default 50,p_offset integer default 0,p_shop_id uuid default null,p_batch_id uuid default null,p_sort text default 'sku',p_since timestamptz default null) returns table(id uuid,shop_id uuid,item_id uuid,color text,size text,sku_code text,quantity integer,active boolean,name text,article_no text,category_id uuid,category_name text,default_price numeric,cost_price numeric,total_count bigint,label_count bigint) language sql stable security invoker set search_path=public as $$
 with args as (select case when public.is_admin() and p_shop_id is null then null else public.resolve_shop(p_shop_id) end sid,coalesce(array(select distinct t from regexp_split_to_table(lower(trim(coalesce(p_q,''))), '\s+') as split(t) where t<>'' order by t),array[]::text[]) tokens),
 token_matches as (select v.id from args a join public.variants v on (a.sid is null and public.is_admin() or v.shop_id=a.sid) cross join lateral unnest(a.tokens) as term(token)
  where v.active and v.search_text ilike '%'||replace(replace(replace(term.token,'\','\\'),'%','\%'),'_','\_')||'%' escape '\'
  group by v.id,a.tokens having count(distinct term.token)=cardinality(a.tokens)),
 matched as (select v.*,i.name,i.article_no,i.category_id,c.name category_name,i.default_price,i.cost_price
 from args a join public.variants v on (a.sid is null and public.is_admin() or v.shop_id=a.sid) join public.items i on i.id=v.item_id left join public.categories c on c.id=i.category_id
  where v.active and (p_category is null or i.category_id=p_category) and (p_size is null or v.size=p_size) and (p_color is null or v.color ilike '%'||p_color||'%')
   and (p_stock='all' or p_stock='in' and v.quantity>0 or p_stock='out' and v.quantity=0 or p_stock='low' and v.quantity<=2)
   and (p_batch_id is null or exists(select 1 from public.stock_entries se where se.variant_id=v.id and se.batch_id=p_batch_id))
   and (p_since is null or exists(select 1 from public.stock_entries se where se.variant_id=v.id and se.created_at>=p_since))
   and (cardinality(a.tokens)=0 or exists(select 1 from token_matches tm where tm.id=v.id))),
 page as (select m.*,count(*) over() total_count,sum(m.quantity) over() label_count from matched m order by (upper(m.sku_code)=upper(trim(coalesce(p_q,'')))) desc,case when p_sort='name' then lower(m.name) end,case when p_sort='article' then lower(m.article_no) end,case when p_sort='color' then lower(m.color) end,case when p_sort='size' then m.size end,m.sku_code limit greatest(1,least(coalesce(p_limit,50),100)) offset greatest(coalesce(p_offset,0),0))
 select p.id,p.shop_id,p.item_id,p.color,p.size,p.sku_code,p.quantity,p.active,p.name,p.article_no,p.category_id,p.category_name,p.default_price,p.cost_price,p.total_count,p.label_count from page p
$$;
create or replace function public.shop_stats(p_shop_id uuid default null) returns table(total_pairs bigint,total_designs bigint,stock_value numeric,sold_today bigint,net_sales_today numeric,sold_this_month numeric,returns_processed_today bigint) language sql stable security invoker set search_path=public as $$
 with s as (select case when public.is_admin() and p_shop_id is null then null else public.resolve_shop(p_shop_id) end sid), bounds as (select timezone('Asia/Kolkata',now())::date today,date_trunc('month',timezone('Asia/Kolkata',now()))::date month_start from s), stock as (select coalesce(sum(v.quantity),0) pairs,count(distinct v.item_id) designs,coalesce(sum(v.quantity*i.default_price),0) value from s join public.variants v on (s.sid is null and public.is_admin() or v.shop_id=s.sid) and v.active join public.items i on i.id=v.item_id), sales as (select count(*) filter(where sa.status='sold' and sa.sold_at at time zone 'Asia/Kolkata'>=b.today and sa.sold_at at time zone 'Asia/Kolkata'<b.today+1) sold_today,coalesce(sum(case when sa.status='sold' then sa.sold_price else -sa.sold_price end) filter(where sa.sold_at at time zone 'Asia/Kolkata'>=b.today and sa.sold_at at time zone 'Asia/Kolkata'<b.today+1),0) net_today,coalesce(sum(case when sa.status='sold' then sa.sold_price else 0 end) filter(where sa.sold_at at time zone 'Asia/Kolkata'>=b.month_start),0) month_sales,count(*) filter(where sa.returned_at at time zone 'Asia/Kolkata'>=b.today and sa.returned_at at time zone 'Asia/Kolkata'<b.today+1) returns_today from s cross join bounds b left join public.sales sa on (s.sid is null and public.is_admin() or sa.shop_id=s.sid))
 select stock.pairs,stock.designs,stock.value,sales.sold_today,sales.net_today,sales.month_sales,sales.returns_today from stock cross join sales
$$;
drop function if exists public.list_sales(uuid,timestamptz,timestamptz,text,text,integer,integer);
drop function if exists public.list_sales(uuid,timestamptz,timestamptz,text,text,integer,integer,uuid);
create or replace function public.list_sales(p_shop_id uuid default null,p_from timestamptz default null,p_to timestamptz default null,p_status text default 'all',p_q text default '',p_limit integer default 50,p_offset integer default 0,p_category uuid default null) returns table(id uuid,shop_id uuid,variant_id uuid,sku_code text,listed_price numeric,sold_price numeric,sold_at timestamptz,status text,returned_at timestamptz,return_reason text,item_name text,article_no text,color text,size text,category_name text,total_count bigint,units_sold bigint,gross_sales numeric,returned_amount numeric,net_sales numeric,returns_today bigint) language sql stable security invoker set search_path=public as $$
 with scope as(select case when public.is_admin() and p_shop_id is null then null else public.resolve_shop(p_shop_id) end sid), bounds as(select timezone('Asia/Kolkata',now())::date td from scope), tokens as(select distinct token from regexp_split_to_table(lower(trim(coalesce(p_q,''))), '\s+') as terms(token) where token<>''), token_matches as(
  select v.id from scope sc join public.variants v on (sc.sid is null and public.is_admin() or v.shop_id=sc.sid) cross join tokens t
  where v.search_text ilike '%'||replace(replace(replace(t.token,'\','\\'),'%','\%'),'_','\_')||'%' escape '\'
  group by v.id having count(distinct t.token)=(select count(*) from tokens)), filtered as (
  select sa.*,i.name item_name,i.article_no,v.color,v.size,c.name category_name,v.search_text
  from scope sc join public.sales sa on (sc.sid is null and public.is_admin() or sa.shop_id=sc.sid)
  join public.variants v on v.id=sa.variant_id join public.items i on i.id=v.item_id left join public.categories c on c.id=i.category_id
  where (p_from is null or sa.sold_at>=p_from) and (p_to is null or sa.sold_at<p_to)
   and (p_status='all' or sa.status=p_status) and (p_category is null or i.category_id=p_category)
   and (not exists(select 1 from tokens) or exists(select 1 from token_matches tm where tm.id=v.id))
 ), totals as(select count(*) total_count,count(*) filter(where status='sold') units_sold,coalesce(sum(sold_price) filter(where status='sold'),0) gross,coalesce(sum(sold_price) filter(where status='returned'),0) returned,coalesce(sum(case when status='sold' then sold_price else -sold_price end),0) net from filtered), todays_returns as(select count(*) n from scope sc join bounds b on true join public.sales s on (sc.sid is null and public.is_admin() or s.shop_id=sc.sid) where s.returned_at at time zone 'Asia/Kolkata'>=b.td and s.returned_at at time zone 'Asia/Kolkata'<b.td+1), page as(select * from filtered order by sold_at desc,id limit greatest(1,least(coalesce(p_limit,50),100)) offset greatest(coalesce(p_offset,0),0))
 select p.id,p.shop_id,p.variant_id,p.sku_code,p.listed_price,p.sold_price,p.sold_at,p.status,p.returned_at,p.return_reason,p.item_name,p.article_no,p.color,p.size,p.category_name,t.total_count,t.units_sold,t.gross,t.returned,t.net,tr.n from page p cross join totals t cross join todays_returns tr
$$;
create or replace function public.ping() returns text language sql security invoker set search_path=public as $$ select 'ok'::text $$;
create or replace function public.shop_colors(p_shop_id uuid default null) returns table(color text) language sql stable security invoker set search_path=public as $$
 with scope as(select case when public.is_admin() and p_shop_id is null then null else public.resolve_shop(p_shop_id) end sid)
 select distinct v.color from scope s join public.variants v on (s.sid is null and public.is_admin() or v.shop_id=s.sid) where trim(v.color)<>'' order by v.color limit 100
$$;
revoke all on function public.resolve_shop(uuid),public.search_variants(text,uuid,text,text,text,integer,integer,uuid,uuid,text,timestamptz),public.shop_stats(uuid),public.list_sales(uuid,timestamptz,timestamptz,text,text,integer,integer,uuid),public.sell_variant(text,numeric,uuid,uuid),public.return_sale(uuid,text,uuid),public.add_stock_batch(jsonb,uuid),public.ping(),public.shop_colors(uuid) from public;
grant execute on function public.resolve_shop(uuid) to authenticated;
grant execute on function public.search_variants(text,uuid,text,text,text,integer,integer,uuid,uuid,text,timestamptz),public.shop_stats(uuid),public.list_sales(uuid,timestamptz,timestamptz,text,text,integer,integer,uuid),public.sell_variant(text,numeric,uuid,uuid),public.return_sale(uuid,text,uuid),public.add_stock_batch(jsonb,uuid),public.ping() to authenticated;
grant execute on function public.shop_colors(uuid) to authenticated;
grant execute on function public.ping() to anon;
revoke all on function public.adjust_stock(uuid,integer,text,uuid) from public;
grant execute on function public.adjust_stock(uuid,integer,text,uuid) to authenticated;
revoke insert,update,delete on public.variants,public.sales,public.stock_entries from authenticated;
grant update(active) on public.variants to authenticated;
grant select on public.variants,public.sales,public.stock_entries to authenticated;

-- OPTIONAL CLEANUP (commented): run manually only if you want to remove the exact
-- SQL safety test fixture created by tests/sell_variant.sql. This does not touch
-- normal inventory, sales, or either production shop.
-- begin;
-- do $$ declare test_shop uuid; begin
--   select id into test_shop from public.shops where name='SQL safety test';
--   if test_shop is not null then
--     delete from public.sales where shop_id=test_shop and variant_id in
--       (select v.id from public.variants v join public.items i on i.id=v.item_id where i.article_no='SQL-NEGATIVE-TEST');
--     delete from public.stock_entries where shop_id=test_shop and variant_id in
--       (select v.id from public.variants v join public.items i on i.id=v.item_id where i.article_no='SQL-NEGATIVE-TEST');
--     delete from public.variants where shop_id=test_shop and item_id in
--       (select id from public.items where article_no='SQL-NEGATIVE-TEST');
--     delete from public.items where shop_id=test_shop and article_no='SQL-NEGATIVE-TEST';
--     delete from public.categories where shop_id=test_shop and name='SQL safety test';
--     delete from public.shops where id=test_shop and name='SQL safety test';
--   end if;
-- end $$;
-- commit;

notify pgrst, 'reload schema';
