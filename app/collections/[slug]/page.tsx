import Store from '@/components/store';
export default async function Page({params}:{params:Promise<{slug:string}>}){const {slug}=await params;return <Store collection={slug}/>}
