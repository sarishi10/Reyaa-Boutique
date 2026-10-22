import {sb} from '@/lib/server';
import {z} from 'zod';
export async function POST(req:Request){try{const token=z.string().uuid().parse(new URL(req.url).searchParams.get('token'));await sb('/rest/v1/subscribers?token=eq.'+token,{method:'PATCH',body:JSON.stringify({unsubscribed:true})},undefined,true);return new Response('Unsubscribed');}catch{return new Response('Invalid or expired request',{status:400});}}
