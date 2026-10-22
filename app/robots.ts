export const dynamic='force-dynamic';
import {getStore} from '@/lib/server';
import {siteOrigin} from '@/lib/site-origin';
export default async function robots(){const {settings}=await getStore();return {rules:{userAgent:'*',disallow:!settings.storeOpen?'/':['/admin','/api','/account']},sitemap:siteOrigin+'/sitemap.xml'};}
