import fs from 'node:fs';
const read=p=>{if(!fs.existsSync(p))throw new Error(`Fichier manquant : ${p}`);return fs.readFileSync(p,'utf8')};
const main=read('src/main.jsx'),journey=read('src/SearchJourney.jsx'),finance=read('src/FinancePanel.jsx'),sql=read('supabase/migration_v7_reservation_finance.sql'),workflow=read('.github/workflows/deploy.yml');
for(const part of ['SearchJourney','HotelWorkspace','FinancePanel','Bookings'])if(!main.includes(part))throw Error(`Navigation manquante : ${part}`);
for(const part of ['hotel_search_v7','hotel_options_v7','submit_booking_with_guests_v8','p_room_count','p_children','À partir de','Voir les offres'])if(!journey.includes(part))throw Error(`Parcours agence incomplet : ${part}`);
for(const part of ['wallet_summary_v7','booking_holds_v7','blocked','spendable'])if(!finance.includes(part))throw Error(`Vue portefeuille incomplète : ${part}`);
for(const part of ['CREATE TABLE IF NOT EXISTS public.booking_holds_v7','CREATE OR REPLACE FUNCTION public.hotel_search_v7','CREATE OR REPLACE FUNCTION public.hotel_options_v7','CREATE OR REPLACE FUNCTION public.submit_booking_v7','CREATE OR REPLACE FUNCTION public.admin_booking_status','CREATE OR REPLACE FUNCTION public.wallet_summary_v7','FOR UPDATE','booking_debit','supplier_payables','REVOKE EXECUTE ON FUNCTION public.submit_booking'])if(!sql.includes(part))throw Error(`Migration financière incomplète : ${part}`);
for(const part of ['VITE_SUPABASE_URL','VITE_SUPABASE_ANON_KEY','npm run build','path: ./dist'])if(!workflow.includes(part))throw Error(`Déploiement incomplet : ${part}`);
console.log('Contrôle structurel V7 : navigation, recherche, blocages, débits, règlements, workflow OK.');
