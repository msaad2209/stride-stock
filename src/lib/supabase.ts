import { createClient } from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL as string|undefined; const key=import.meta.env.VITE_SUPABASE_ANON_KEY as string|undefined;
export const configured=Boolean(url&&key); export const supabase=configured?createClient(url!,key!):null;
export type Variant= {id:string;shop_id:string;item_id:string;color:string;size:string;sku_code:string;quantity:number;active:boolean;items:{name:string;article_no:string;default_price:number;cost_price:number;category_id:string;categories?:{name:string}}};
