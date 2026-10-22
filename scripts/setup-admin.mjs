import {randomBytes} from 'node:crypto';
const email=process.env.ADMIN_EMAIL||'nisha.nairofficial0728@gmail.com';
const url=process.env.SUPABASE_URL,key=process.env.SUPABASE_SECRET_KEY;
if(!url||!key)throw Error('Set SUPABASE_URL and SUPABASE_SECRET_KEY in your private .env.local first.');
async function api(path,method='GET',body){const r=await fetch(url+'/auth/v1/'+path,{method,headers:{apikey:key,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const data=await r.json();if(!r.ok)throw Error(data.msg||data.message||'Supabase Auth request failed');return data;}
let existing;
for(let page=1;page<=100;page++){const result=await api('admin/users?page='+page+'&per_page=1000');existing=result.users?.find(u=>u.email?.toLowerCase()===email.toLowerCase());if(existing||!result.users?.length||result.users.length<1000)break;}
if(existing?.app_metadata?.store_role==='admin'){console.log('Administrator already exists: '+email+'\nUse Forgot password in /admin. No password was changed.');process.exit(0);}
if(existing){await api('admin/users/'+existing.id,'PUT',{app_metadata:{...existing.app_metadata,store_role:'admin',must_change_password:true}});console.log('Administrator assigned: '+email+'\nExisting password preserved. Use Forgot password in /admin to verify email ownership and choose a new password.');}
else{const password='Reyaa!'+randomBytes(24).toString('base64url');await api('admin/users','POST',{email,password,email_confirm:true,app_metadata:{store_role:'admin',must_change_password:true},user_metadata:{name:'Reyaa administrator'}});console.log('Administrator created: '+email+'\nTemporary password (shown only now): '+password+'\nThis password cannot open store management. Use Forgot password in /admin and complete the email reset first.');}
