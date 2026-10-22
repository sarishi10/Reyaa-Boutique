-- REYAA: NEW EMPTY SUPABASE PROJECT ONLY. Run once.
BEGIN;
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

-- Apply after store-schema.sql in the dedicated Reyaa project.
alter table public.orders add column customer_id uuid references auth.users(id) on delete set null;
alter table public.orders add column request_key uuid unique;
alter table public.orders add column bill_id text unique;
alter table public.orders add column bill_url text;
alter table public.orders add column payment_provider text;
alter table public.orders add column shipping_fee numeric(12,2) not null default 0;
alter table public.orders add column fulfillment text not null default 'processing' check(fulfillment in ('processing','packed','shipped','delivered'));
alter table public.orders add column carrier text not null default '';
alter table public.orders add column tracking_number text not null default '';
alter table public.orders add column tracking_url text not null default '';
alter table public.orders add column shipped_at timestamptz;
alter table public.orders add column delivered_at timestamptz;
create index orders_customer_idx on public.orders(customer_id,created_at desc);
grant select on public.orders,public.order_items to authenticated;
create policy own_orders on public.orders for select to authenticated using(customer_id=(select auth.uid()));
create policy own_order_items on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.customer_id=(select auth.uid())));

create function public.reserve_bill_order(uid uuid,request_key uuid,customer_data jsonb,cart_items jsonb,fee numeric) returns jsonb language plpgsql security invoker set search_path='' as $$
declare o public.orders; i jsonb; v record; q integer; subtotal numeric=0;
begin
 perform pg_advisory_xact_lock(hashtext(uid::text));
 select * into o from public.orders where orders.request_key=reserve_bill_order.request_key;
 if found then
  if o.customer_id<>uid then raise exception 'Request belongs to another customer';end if;
  if o.status<>'pending' then raise exception 'Order already completed or cancelled';end if;
  return to_jsonb(o)||jsonb_build_object('claimed',false);
 end if;
 if exists(select 1 from public.orders where customer_id=uid and status='pending' and payment_provider='billplz') then raise exception 'You have a pending order. Complete or cancel it in My Account first.';end if;
 if jsonb_array_length(cart_items)<1 or jsonb_array_length(cart_items)>30 or fee<0 or fee>10000 then raise exception 'Invalid cart';end if;
 insert into public.orders(customer_id,request_key,customer,total,shipping_fee,payment_provider) values(uid,request_key,customer_data,0,fee,'billplz') returning * into o;
 for i in select value from jsonb_array_elements(cart_items) order by value->>'variantId' loop
  q=(i->>'qty')::integer;
  if q<1 or q>20 then raise exception 'Invalid quantity';end if;
  select pv.*,p.name,coalesce(p.sale_price,p.price) as unit_price into v from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=i->>'variantId' and p.id=i->>'productId' and p.published for update of pv;
  if not found or v.stock<q then raise exception 'An item is no longer available. Refresh your bag.';end if;
  update public.product_variants set stock=stock-q where id=v.id;
  insert into public.order_items(order_id,variant_id,name,size,color,unit_price,quantity) values(o.id,v.id,v.name,v.size,v.color,v.unit_price,q);
  subtotal=subtotal+v.unit_price*q;
 end loop;
 if subtotal+fee<=0 then raise exception 'Invalid payment amount';end if;
 update public.orders set total=subtotal+fee where id=o.id returning * into o;
 return to_jsonb(o)||jsonb_build_object('claimed',true);
end $$;
create function public.attach_bill(oid uuid,bid text,burl text) returns void language plpgsql security invoker set search_path='' as $$
declare o public.orders;
begin
 select * into o from public.orders where id=oid for update;
 if not found or o.payment_provider is distinct from 'billplz' or (o.bill_id is not null and o.bill_id is distinct from bid) then raise exception 'Bill conflict';end if;
 update public.orders set bill_id=bid,bill_url=burl where id=oid;
end $$;
create function public.settle_bill(oid uuid,bid text,amount_sen bigint,paid_sen bigint) returns void language plpgsql security invoker set search_path='' as $$
declare o public.orders;
begin
 select * into o from public.orders where id=oid for update;
 if not found or o.bill_id is distinct from bid or o.payment_provider is distinct from 'billplz' or round(o.total*100)<>amount_sen or paid_sen<>amount_sen then raise exception 'Payment mismatch';end if;
 if o.payment_status='paid' then return;end if;
 if o.status<>'pending' then raise exception 'Order requires manual payment review';end if;
 -- Inventory was reserved atomically before redirect. Never deduct twice.
 update public.orders set payment_status='paid',status='confirmed',confirmed_at=now() where id=oid;
end $$;
create function public.release_bill_order(oid uuid) returns void language plpgsql security invoker set search_path='' as $$
declare o public.orders;i record;
begin
 select * into o from public.orders where id=oid for update;
 if not found then raise exception 'Order not found';end if;
 if o.status='cancelled' then return;end if;
 if o.payment_status<>'unpaid' or o.status<>'pending' or o.payment_provider is distinct from 'billplz' then raise exception 'Cannot release this order';end if;
 -- Server calls only after Billplz confirms bill deletion, never on a timer.
 for i in select * from public.order_items where order_id=oid order by variant_id loop
 if i.variant_id is null then raise exception 'Missing reserved variant';end if;
 update public.product_variants set stock=stock+i.quantity where id=i.variant_id;
 end loop;
 update public.orders set status='cancelled' where id=oid;
end $$;
-- A reserved variant cannot disappear while a Bill can still be paid.
create function public.protect_reserved_variant() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if exists(select 1 from public.order_items i join public.orders o on o.id=i.order_id where i.variant_id=old.id and o.status='pending' and o.payment_provider='billplz') then raise exception 'Cancel pending payments before deleting this variant';end if;
 return old;
end $$;
create trigger protect_reserved_variant before delete on public.product_variants for each row execute function public.protect_reserved_variant();

create table public.subscribers(id uuid primary key default gen_random_uuid(),email text unique not null,confirmed boolean not null default false,unsubscribed boolean not null default false,token uuid not null default gen_random_uuid(),created_at timestamptz not null default now(),requested_at timestamptz not null default now(),confirmed_at timestamptz);
create table public.campaigns(id uuid primary key default gen_random_uuid(),subject text not null,body text not null,status text not null default 'draft' check(status in ('draft','queued')),created_at timestamptz not null default now());
create table public.campaign_deliveries(id uuid primary key default gen_random_uuid(),campaign_id uuid not null references public.campaigns(id),subscriber_id uuid not null references public.subscribers(id),status text not null default 'queued' check(status in ('queued','sending','sent','skipped','review')),provider_id text,created_at timestamptz not null default now(),unique(campaign_id,subscriber_id));
create index campaign_deliveries_queue_idx on public.campaign_deliveries(campaign_id,status);
create index campaign_deliveries_subscriber_idx on public.campaign_deliveries(subscriber_id);
alter table public.subscribers enable row level security;
alter table public.campaigns enable row level security;
alter table public.campaign_deliveries enable row level security;
grant all on public.subscribers,public.campaigns,public.campaign_deliveries to service_role;
-- No public or customer SELECT on subscriber addresses or admin campaigns.
create function public.request_subscription(address text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.subscribers;
begin
 perform pg_advisory_xact_lock(hashtext(lower(address)));
 select * into s from public.subscribers where email=lower(address);
 if found and (s.requested_at>now()-interval '10 minutes' or (s.confirmed and not s.unsubscribed)) then return null;end if;
 insert into public.subscribers(email) values(lower(address)) on conflict(email) do update set token=gen_random_uuid(),requested_at=now() returning * into s;
 return to_jsonb(s);
end $$;
create function public.queue_campaign(cid uuid) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from public.campaigns where id=cid and status='draft' for update;
 if not found then raise exception 'Campaign already queued or missing';end if;
 insert into public.campaign_deliveries(campaign_id,subscriber_id) select cid,id from public.subscribers where confirmed and not unsubscribed;
 update public.campaigns set status='queued' where id=cid;
end $$;
create function public.claim_delivery(cid uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare d public.campaign_deliveries;
begin
 select * into d from public.campaign_deliveries where campaign_id=cid and status='queued' order by created_at for update skip locked limit 1;
 if not found then return null;end if;
 update public.campaign_deliveries set status='sending' where id=d.id;
 return to_jsonb(d);
end $$;
revoke all on function public.reserve_bill_order(uuid,uuid,jsonb,jsonb,numeric),public.attach_bill(uuid,text,text),public.settle_bill(uuid,text,bigint,bigint),public.release_bill_order(uuid),public.protect_reserved_variant(),public.request_subscription(text),public.queue_campaign(uuid),public.claim_delivery(uuid) from public,anon,authenticated;
grant execute on function public.reserve_bill_order(uuid,uuid,jsonb,jsonb,numeric),public.attach_bill(uuid,text,text),public.settle_bill(uuid,text,bigint,bigint),public.release_bill_order(uuid),public.protect_reserved_variant(),public.request_subscription(text),public.queue_campaign(uuid),public.claim_delivery(uuid) to service_role;
-- Durable signup abuse limits; no raw client IP addresses are stored.
create table public.signup_limits(key text primary key,hits integer not null,window_start timestamptz not null);
alter table public.signup_limits enable row level security;
grant all on public.signup_limits to service_role;
create function public.limit_signup(client_key text) returns void language plpgsql security invoker set search_path='' as $$
declare k text;n integer;cap integer;
begin
 delete from public.signup_limits where window_start<now()-interval '2 days';
 foreach k in array array['global',client_key] loop
  cap=case when k='global' then 200 else 5 end;
  insert into public.signup_limits(key,hits,window_start) values(k,1,date_trunc('hour',now())) on conflict(key) do update set hits=case when signup_limits.window_start=date_trunc('hour',now()) then signup_limits.hits+1 else 1 end,window_start=date_trunc('hour',now()) returning hits into n;
  if n>cap then raise exception 'Too many subscription requests. Please try again later.';end if;
 end loop;
end $$;
revoke all on function public.limit_signup(text) from public,anon,authenticated;
grant execute on function public.limit_signup(text) to service_role;

COMMIT;
