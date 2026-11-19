// Contrôles structurels sans serveur ni connexion Supabase.
import fs from 'node:fs';
const requireFile=p=>{if(!fs.existsSync(p))throw Error('Fichier absent : '+p);return fs.readFileSync(p,'utf8')};
const main=requireFile('src/main.jsx');const hotel=requireFile('src/HotelWorkspace.jsx');const excel=requireFile('src/excel.js');const migration=requireFile('supabase/migration_v6_catalogue.sql');const css=requireFile('src/style.css');
for(const s of ['HotelWorkspace','SearchPanel','FinancePanel'])if(!main.includes(s))throw Error('Module absent : '+s);
for(const s of ['import_hotel_excel_v6','hotel_promotions','hotel_promotion_periods','CREATE POLICY room_read','public.hotel_offers','public.submit_booking'])if(!migration.includes(s))throw Error('Migration incomplète : '+s);
for(const s of ['DEFAULT_ROOMS','DEFAULT_PROMOS','parseNatbeds','dateRange','discount_percent'])if(!excel.includes(s))throw Error('Parseur Excel incomplet : '+s);
for(const s of ['Créer','hotel_promotions','import_hotel_excel_v6','hotel_promotion_periods','is_public'])if(!hotel.includes(s))throw Error('Catalogue incomplet : '+s);
if(!css.startsWith('@import'))throw Error('Import de police CSS déplacé ou absent');
for(const s of ['modele_tarifs_natbeds.xlsx','exemple_tarifs_fictifs.xlsx','.github/workflows/deploy.yml'])if(!fs.existsSync(s))throw Error('Ressource absente : '+s);
console.log('Structure V6 : fichiers, RPC, migration, import, catalogue, polices, workflow OK.');
