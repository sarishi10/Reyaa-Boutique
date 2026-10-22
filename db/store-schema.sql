-- Dedicated store database schema. Apply only to the new boutique project.
create table public.store_settings(id text primary key check(id='main'),data jsonb not null);
create table public.products(id text primary key,slug text unique not null,name text not null,category text not null,price numeric(12,2) not null check(price>=0),sale_price numeric(12,2) check(sale_price>=0 and sale_price<price),images jsonb not null default '[]',description text not null default '',care text not null default '',sku text not null default '',published boolean not null default false,featured boolean not null default false,created_at timestamptz not null default now());
create table public.product_variants(id text primary key,product_id text not null references public.products(id) on delete cascade,size text not null,color text not null default '',stock integer not null default 0 check(stock>=0));
create index product_variants_product_idx on public.product_variants(product_id);
create table public.orders(id uuid primary key default gen_random_uuid(),customer jsonb not null,total numeric(12,2) not null check(total>=0),status text not null default 'pending' check(status in ('pending','confirmed','cancelled')),payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid','refunded')),created_at timestamptz not null default now(),confirmed_at timestamptz);
create table public.order_items(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,variant_id text references public.product_variants(id) on delete set null,name text not null,size text not null,color text not null,unit_price numeric(12,2) not null check(unit_price>=0),quantity integer not null check(quantity>0));
create index order_items_order_idx on public.order_items(order_id);
create index order_items_variant_idx on public.order_items(variant_id);
create index orders_created_idx on public.orders(created_at desc);
alter table public.store_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
grant select on public.store_settings,public.products,public.product_variants to anon,authenticated;
grant all on public.store_settings,public.products,public.product_variants,public.orders,public.order_items to service_role;
create policy settings_public on public.store_settings for select to anon,authenticated using(true);
create policy products_public on public.products for select to anon,authenticated using(published);
create policy variants_public on public.product_variants for select to anon,authenticated using(exists(select 1 from public.products p where p.id=product_id and p.published));
-- No client policies on orders. Server endpoints validate administrator identity
-- against Auth and use a server-only secret. No client can mutate catalog or stock.
create function public.save_product(payload jsonb) returns void language plpgsql security invoker set search_path='' as $$
begin
 insert into public.products(id,slug,name,category,price,sale_price,images,description,care,sku,published,featured,created_at)
 values(payload->>'id',payload->>'slug',payload->>'name',payload->>'category',(payload->>'price')::numeric,(payload->>'sale_price')::numeric,payload->'images',payload->>'description',payload->>'care',payload->>'sku',(payload->>'published')::boolean,(payload->>'featured')::boolean,(payload->>'created_at')::timestamptz)
 on conflict(id) do update set slug=excluded.slug,name=excluded.name,category=excluded.category,price=excluded.price,sale_price=excluded.sale_price,images=excluded.images,description=excluded.description,care=excluded.care,sku=excluded.sku,published=excluded.published,featured=excluded.featured;
 if exists(select 1 from jsonb_array_elements(payload->'variants') v join public.product_variants pv on pv.id=v->>'id' where pv.product_id<>payload->>'id') then raise exception 'Variant belongs to another product';end if;
 delete from public.product_variants where product_id=payload->>'id' and id not in(select v->>'id' from jsonb_array_elements(payload->'variants') v);
 insert into public.product_variants(id,product_id,size,color,stock) select v->>'id',payload->>'id',v->>'size',v->>'color',(v->>'stock')::integer from jsonb_array_elements(payload->'variants') v
 on conflict(id) do update set size=excluded.size,color=excluded.color,stock=excluded.stock;
end $$;
create function public.create_pending_order(customer_data jsonb,cart_items jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare oid uuid; item jsonb; variant record; line_total numeric=0; grand_total numeric=0; result_items jsonb='[]'::jsonb; q integer;
begin
 if jsonb_array_length(cart_items)<1 or jsonb_array_length(cart_items)>30 then raise exception 'Invalid cart size';end if;
 -- Transaction advisory lock limits duplicate rapid submissions for the same phone.
 perform pg_advisory_xact_lock(hashtext(customer_data->>'phone'));
 if exists(select 1 from public.orders where customer->>'phone'=customer_data->>'phone' and created_at>now()-interval '30 seconds') then raise exception 'Please wait before submitting another order.';end if;
 insert into public.orders(customer,total) values(customer_data,0) returning id into oid;
 for item in select value from jsonb_array_elements(cart_items) loop
 q=(item->>'qty')::integer;
 if q<1 or q>50 then raise exception 'Invalid quantity';end if;
 select v.*,p.name,coalesce(p.sale_price,p.price) as unit_price into variant from public.product_variants v join public.products p on p.id=v.product_id where v.id=item->>'variantId' and p.id=item->>'productId' and p.published;
 if not found or variant.stock<q then raise exception 'An item is unavailable. Please refresh your bag.';end if;
 insert into public.order_items(order_id,variant_id,name,size,color,unit_price,quantity) values(oid,variant.id,variant.name,variant.size,variant.color,variant.unit_price,q);
 grand_total=grand_total+variant.unit_price*q;
 result_items=result_items||jsonb_build_array(jsonb_build_object('name',variant.name,'size',variant.size,'color',variant.color,'unit_price',variant.unit_price,'quantity',q));
 end loop;
 update public.orders set total=grand_total where id=oid;
 return jsonb_build_object('id',oid,'total',grand_total,'items',result_items);
end $$;
create function public.confirm_order(order_id uuid) returns void language plpgsql security invoker set search_path='' as $$
declare current_status text; item record; available integer;
begin
 select status into current_status from public.orders where id=order_id for update;
 if not found then raise exception 'Order not found';end if;
 if current_status='confirmed' then return;end if;
 if current_status<>'pending' then raise exception 'Only pending orders can be confirmed';end if;
 for item in select i.variant_id,sum(i.quantity)::integer as quantity from public.order_items i where i.order_id=confirm_order.order_id group by i.variant_id order by i.variant_id loop
 if item.variant_id is null then raise exception 'An ordered variant has been deleted';end if;
 select stock into available from public.product_variants where id=item.variant_id for update;
 if not found or available<item.quantity then raise exception 'Insufficient stock. Order remains pending.';end if;
 update public.product_variants set stock=stock-item.quantity where id=item.variant_id;
 end loop;
 update public.orders set status='confirmed',confirmed_at=now() where id=order_id;
end $$;
revoke all on function public.save_product(jsonb),public.create_pending_order(jsonb,jsonb),public.confirm_order(uuid) from public,anon,authenticated;
grant execute on function public.save_product(jsonb),public.create_pending_order(jsonb,jsonb),public.confirm_order(uuid) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('store-images','store-images',true,8388608,array['image/jpeg','image/png','image/webp']);
-- Storage mutations are server-only; public bucket serves catalog photos.
