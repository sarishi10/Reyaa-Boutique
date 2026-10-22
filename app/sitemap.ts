export const dynamic='force-dynamic';
import {getStore} from '@/lib/server';
import {siteOrigin} from '@/lib/site-origin';
export default async function sitemap(){const {products}=await getStore();return [{url:siteOrigin,lastModified:new Date()},...products.map((p:any)=>({url:siteOrigin+'/products/'+p.slug,lastModified:new Date(p.created_at)})),{url:siteOrigin+'/collections/all'}];}
