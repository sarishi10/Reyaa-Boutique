import Store from '@/components/store';
export default async function Page({params}:{params:Promise<{page:string}>}){const {page}=await params;return <Store infoPage={page}/>}
