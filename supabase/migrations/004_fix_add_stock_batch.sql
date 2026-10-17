-- 004: repair add_stock_batch (fixes "column cost_price is of type numeric but expression is of type text"
-- and PL/pgSQL "column reference is ambiguous" errors). Safe to run more than once.
-- Does NOT change data and does NOT change the schema version (stays 3).
create or replace function public.add_stock_batch(p_payload jsonb,p_shop_id uuid default null) returns table(batch_id uuid,variant_id uuid,sku_code text,color text,size text,quantity integer,item_name text,article_no text,default_price numeric) language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare sid uuid; b uuid:=gen_random_uuid(); payload jsonb; iid uuid; cid uuid; variant_row public.variants; qty integer; begin
 sid:=public.resolve_shop(p_shop_id);
 if jsonb_typeof(p_payload)<>'object' or jsonb_typeof(p_payload->'variants')<>'array' or jsonb_array_length(p_payload->'variants')=0 then raise exception 'Stock batch must include variants'; end if;
 if coalesce(trim(p_payload->>'name'),'')='' or coalesce(trim(p_payload->>'article_no'),'')='' then raise exception 'Item name and article number are required'; end if;
 cid:=(p_payload->>'category_id')::uuid;
 if not exists(select 1 from public.categories where id=cid and shop_id=sid and active) then raise exception 'Choose an active category in this shop'; end if;
 perform pg_advisory_xact_lock(hashtextextended(sid::text||lower(trim(p_payload->>'article_no')),0));
 select id into iid from public.items where shop_id=sid and lower(article_no)=lower(trim(p_payload->>'article_no')) for update;
 if found then update public.items set name=trim(p_payload->>'name'),category_id=cid,default_price=(p_payload->>'default_price')::numeric,cost_price=nullif(trim(coalesce(p_payload->>'cost_price','')),'')::numeric where id=iid;
 else insert into public.items(shop_id,name,article_no,category_id,default_price,cost_price) values(sid,trim(p_payload->>'name'),trim(p_payload->>'article_no'),cid,(p_payload->>'default_price')::numeric,nullif(trim(coalesce(p_payload->>'cost_price','')),'')::numeric) returning id into iid; end if;
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

notify pgrst, 'reload schema';
