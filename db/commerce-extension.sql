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
