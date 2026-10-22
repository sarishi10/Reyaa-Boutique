import {sb} from './server';
export const initialAdminEmail=()=>process.env.ADMIN_EMAIL||'nisha.nairofficial0728@gmail.com';
export const adminCookie=(name:string,value:string,maxAge:number)=>`${name}=${encodeURIComponent(value)}; HttpOnly;${process.env.NODE_ENV==='production'?' Secure;':''} SameSite=Strict; Path=/; Max-Age=${maxAge}`;
export async function verifiedAdministrator(token:string){const user=await sb('/auth/v1/user',{},token);if(!user?.id||!user.email_confirmed_at||user.app_metadata?.store_role!=='admin')throw Error('A valid administrator reset session is required.');// Supabase has verified this exact JWT above. Only then inspect signed claims.
let claims:any;try{claims=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));}catch{throw Error('Invalid reset session.');}
const now=Math.floor(Date.now()/1000);if(claims.sub!==user.id||!Array.isArray(claims.amr)||!claims.amr.some((a:any)=>a.method==='recovery'&&Number.isFinite(a.timestamp)&&a.timestamp<=now+30&&a.timestamp>=now-900))throw Error('Open a fresh password reset link from your administrator email.');return user;}
