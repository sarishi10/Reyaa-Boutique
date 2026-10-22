import {getStore} from '@/lib/server';
export async function GET(){try{return Response.json({...await getStore(),paymentMode:process.env.BILLPLZ_MODE||'unconfigured'});}catch{return Response.json({error:'Store temporarily unavailable. Please try again.'},{status:503});}}
