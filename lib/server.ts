import {settings} from './catalog';
export const configured=()=>!!(process.env.SUPABASE_URL&&process.env.SUPABASE_PUBLISHABLE_KEY&&process.env.SUPABASE_SECRET_KEY);
export async function sb(path:string,init:RequestInit={},token?:string,secret=false){
 const key=secret?process.env.SUPABASE_SECRET_KEY:process.env.SUPABASE_PUBLISHABLE_KEY;
 if(!configured()) throw new Error('Store database is not connected yet.');
 const r=await fetch(process.env.SUPABASE_URL+path,{...init,headers:{apikey:key!,...(token?{Authorization:'Bearer '+token}:{}),'Content-Type':'application/json',...init.headers},cache:'no-store'});
 const d:any=await r.json().catch(()=>null);if(!r.ok)throw new Error(d?.msg||d?.message||d?.error_description||'Database request failed');return d;
}
export async function getStore(){if(!configured())return {settings,products:[],connected:false};const [s,p]=await Promise.all([sb('/rest/v1/store_settings?id=eq.main&select=data'),sb('/rest/v1/products?select=*,variants:product_variants(*)&published=eq.true&order=created_at.desc')]);return {settings:{...settings,...s[0]?.data},products:p,connected:true};}
export function tokenOf(req:Request){return decodeURIComponent((req.headers.get('cookie')||'').split('; ').find(s=>s.startsWith('store_session='))?.slice(14)||'');}
export async function admin(req:Request){const token=tokenOf(req);if(!token)throw new Error('Please sign in.');const user=await sb('/auth/v1/user',{},token);if(user?.app_metadata?.store_role!=='admin')throw new Error('Administrator access required.');if(user.app_metadata.must_change_password)throw new Error('Reset your temporary password using the email link before managing the store.');return token;}
export function sameOrigin(req:Request){const origin=req.headers.get('origin');if(!origin||origin!==new URL(req.url).origin)throw new Error('Invalid request origin.');}
