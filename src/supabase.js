import {createClient} from '@supabase/supabase-js';
const url=(import.meta.env.VITE_SUPABASE_URL||'').trim();
const key=(import.meta.env.VITE_SUPABASE_ANON_KEY||'').trim();
export const configured=/^https:\/\/[^\s/]+/.test(url) && key.length>20 && !url.includes('xxxxx') && !key.includes('ta_cle');
// Jamais de service_role/secret key dans le navigateur.
export const supabase=configured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
export const euro=n=>new Intl.NumberFormat('fr-FR',{style:'currency',currency:'EUR'}).format(Number(n||0));
export const iso=d=>new Date(d+'T12:00:00Z').toLocaleDateString('fr-FR');
