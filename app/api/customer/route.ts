import {configured,sameOrigin,sb} from '@/lib/server';
import {customer,cookie,sessionResponse,publicOrigin} from '@/lib/customer';
import {z} from 'zod';
export async function GET(req:Request){try{const {user,token}=await customer(req);const orders=await sb('/rest/v1/orders?select=*,items:order_items(*)&order=created_at.desc&limit=100',{},token);return Response.json({user:{email:user.email,name:user.user_metadata?.name||''},orders},{headers:{'Cache-Control':'no-store'}});}catch{return Response.json({error:'Please sign in.'},{status:401});}}
export async function POST(req:Request){try{sameOrigin(req);if(!configured())return Response.json({error:'Customer accounts will open when store setup is complete.'},{status:503});const b:any=await req.json();
if(b.action==='logout'){const token=cookie(req,'customer_session');if(token)await sb('/auth/v1/logout?scope=local',{method:'POST'},token).catch(()=>{});return sessionResponse({ok:true},{});}
if(b.action==='refresh'){const refresh_token=cookie(req,'customer_refresh');if(!refresh_token)throw Error('Please sign in.');const d=await sb('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:JSON.stringify({refresh_token})});return sessionResponse({ok:true},d);}
if(b.action==='session'){const access=z.string().min(20).max(10000).parse(b.access_token);const u=await sb('/auth/v1/user',{},access);if(!u.email_confirmed_at)throw Error('Please confirm your email.');return sessionResponse({ok:true},{access_token:access,refresh_token:z.string().max(10000).parse(b.refresh_token),expires_in:3600});}
if(b.action==='password'){const {token}=await customer(req);const password=z.string().min(12).max(128).parse(b.password);await sb('/auth/v1/user',{method:'PUT',body:JSON.stringify({password})},token);return Response.json({ok:true,message:'Password updated.'});}
const email=z.string().email().max(254).parse(b.email).toLowerCase();
if(b.action==='recover'){await sb('/auth/v1/recover?redirect_to='+encodeURIComponent(publicOrigin()+'/account'),{method:'POST',body:JSON.stringify({email})});return Response.json({message:'If an account exists, check your email for a password reset link.'});}
const password=z.string().min(b.action==='signup'?12:1).max(128).parse(b.password);
if(b.action==='signup'){const name=z.string().min(2).max(100).parse(b.name);await sb('/auth/v1/signup?redirect_to='+encodeURIComponent(publicOrigin()+'/account'),{method:'POST',body:JSON.stringify({email,password,data:{name}})});return Response.json({message:'Check your email to confirm your account, then sign in.'});}
if(b.action==='login'){const d=await sb('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email,password})});if(!d.user.email_confirmed_at)throw Error('Please confirm your email.');return sessionResponse({ok:true},d);}
throw Error('Unknown account action.');
}catch(e){return Response.json({error:(e as Error).message},{status:400});}}
