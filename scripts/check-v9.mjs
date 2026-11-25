import fs from 'node:fs';
const get=f=>fs.readFileSync(f,'utf8');
const needed={
 'src/main.jsx':['normalizeRoute','sidebar-compact','/settings','FinanceActions','PartnersPages','SuppliersPages','AccountSettings'],
 'src/HotelWorkspace.jsx':['delete_draft_hotel_v9','/hotels/new','import_hotel_excel_v6','exportRates','/delete'],
 'src/SearchJourney.jsx':['hotel_search_v7','hotel_options_v7','/search/hotel/','submit_booking_with_guests_v8'],
 'src/AccountSettings.jsx':['account-avatars','auth.updateUser','avatar_url','bio','phone','company'],
 'src/FinanceActions.jsx':['wallet_topup_requests','admin_wallet_entry','admin_create_payable','admin_review_topup'],
 'src/AgencyConditions.jsx':['agency_hotel_markups','admin_set_hotel_markup_v8','/delete'],
 'src/ContractsPanel.jsx':['hotel_contracts_v8','/contracts/new','/delete'],
 'src/excel.js':['parseNatbeds','exportRates','DEFAULT_ROOMS','DEFAULT_PROMOS'],
 'supabase/migration_v9_compte_navigation.sql':['profiles_v9_update_self','account-avatars','delete_draft_hotel_v9','REVOKE UPDATE'],
 '.github/workflows/deploy.yml':['npm run build','npm run check:dist','VITE_SUPABASE_URL','VITE_SUPABASE_ANON_KEY'],
};
for(const [name,checks] of Object.entries(needed)){if(!fs.existsSync(name))throw Error('Missing: '+name);const source=get(name);for(const key of checks)if(!source.includes(key))throw Error(`${name}: missing ${key}`)}
for(const f of ['public/modele_tarifs_natbeds.xlsx','public/exemple_tarifs_fictifs.xlsx'])if(!fs.existsSync(f)||fs.statSync(f).size<1000)throw Error('Invalid Excel template: '+f);
console.log('V9 : routing, catalogue, comptes, finance, SQL, Excel et déploiement : OK');
