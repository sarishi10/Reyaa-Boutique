import type { Metadata } from 'next';
import {getStore} from '@/lib/server';
import {siteOrigin} from '@/lib/site-origin';
import './globals.css';
export const dynamic='force-dynamic';
export async function generateMetadata():Promise<Metadata>{const {settings:s}=await getStore();return {metadataBase:new URL(siteOrigin),title:s.seoTitle,description:s.seoDescription,robots:{index:s.storeOpen,follow:s.storeOpen},openGraph:{title:s.seoTitle,description:s.seoDescription,type:'website',images:[s.heroImage]},icons:{icon:'/images/reyaa-logo.png',apple:'/images/reyaa-logo.png'}};}
export default function Layout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}
