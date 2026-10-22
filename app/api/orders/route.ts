import {getStore,sameOrigin,sb} from '@/lib/server';
import {customer} from '@/lib/customer';
import {paymentReady,createBill,reconcileBill,cancelBillOrder} from '@/lib/payments';
import {z} from 'zod';
export async function POST(req:Request){try{sameOrigin(req);const {user}=await customer(req);const b:any=await req.json();
if(['recheck','cancel'].includes(b.action)){const id=z.string().uuid().parse(b.id);const [o]=await sb('/rest/v1/orders?id=eq.'+id+'&customer_id=eq.'+user.id,{},undefined,true);if(!o)throw Error('Order not found.');if(b.action==='cancel')await cancelBillOrder(o);else if(o.bill_id&&o.payment_status!=='paid')await reconcileBill(o.id,o.bill_id);return Response.json({ok:true});}
const parsed=z.object({requestId:z.string().uuid(),items:z.array(z.object({productId:z.string().max(100),variantId:z.string().max(100),qty:z.number().int().min(1).max(20)})).min(1).max(30),customer:z.object({name:z.string().min(2).max(100),phone:z.string().min(7).max(25),address:z.string().min(8).max(500),region:z.enum(['MY-West','MY-East'])})}).parse(b);
const {settings:s}=await getStore();if(!s.storeOpen||!s.shippingConfigured||s.currency!=='MYR'||s.checkoutMode!=='billplz'||!paymentReady())throw Error('Checkout is not open yet. Please contact the boutique.');if(new Set(parsed.items.map(i=>i.variantId)).size!==parsed.items.length)throw Error('Duplicate variants are not allowed.');
const order=await sb('/rest/v1/rpc/reserve_bill_order',{method:'POST',body:JSON.stringify({uid:user.id,request_key:parsed.requestId,customer_data:{...parsed.customer,email:user.email},cart_items:parsed.items,fee:s.shippingFee})},undefined,true);
if(order.bill_url)return Response.json({id:order.id,paymentUrl:order.bill_url});if(!order.claimed)throw Error('A payment is already being prepared. Check My Account before trying again.');
// Never retry an ambiguous POST to Billplz: reconcile it in the admin portal.
try{const bill=await createBill(order);if(!/^https:\/\/(www\.)?billplz(-sandbox)?\.com\//.test(bill.url)||!bill.id)throw Error('Unexpected payment response.');await sb('/rest/v1/rpc/attach_bill',{method:'POST',body:JSON.stringify({oid:order.id,bid:bill.id,burl:bill.url})},undefined,true);return Response.json({id:order.id,paymentUrl:bill.url});}catch{throw Error('Payment creation needs review. Your order is saved in My Account; please contact the boutique.');}
}catch(e){return Response.json({error:(e as Error).message},{status:400});}}
