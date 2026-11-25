import React,{useEffect,useState} from 'react';
import {Plug,FlaskConical,ShieldCheck,Hotel,RefreshCw} from 'lucide-react';
import {supabase} from './supabase';
const q=async p=>{const {data,error}=await p;if(error)throw Error(error.message);return data};
export default function RatehawkDemo({notify,fail}){
 const [items,setItems]=useState([]),[active,setActive]=useState(true),[busy,setBusy]=useState(false);
 async function load(){try{const [d,s]=await Promise.all([q(supabase.from('demo_ratehawk_hotels_v8').select('hotel_id,provider_code,hotels(name,city,status)')),q(supabase.from('netbeds_demo_settings_v8').select('enabled').eq('id',true).single())]);setItems(d);setActive(s.enabled)}catch(e){fail(e)}}
 useEffect(()=>{load()},[]);
 async function run(fn){setBusy(true);try{await fn();await load();notify('Configuration du fournisseur simulé mise à jour')}catch(e){fail(e)}finally{setBusy(false)}}
 return <section><div className="work-header"><div><span className="eyebrow">FOURNISSEURS / CONNECTEURS</span><h2>Connecteur RateHawk simulé</h2><p>Préparation de l'intégration et tests de réservation sans accès API.</p></div><FlaskConical size={32}/></div>
 <div className="alert info"><ShieldCheck size={17}/> Aucun appel à RateHawk. Les hôtels, disponibilités et confirmations sont fictifs. Ce module ne remplace pas le sandbox officiel.</div>
 <div className="finance-grid"><div className="card"><h3><Plug size={19}/> Environnement</h3><p>Mode actif : <b>{active?'Simulation activée':'Simulation désactivée'}</b></p><p>Le connecteur réel exigera des identifiants API conservés dans les secrets Supabase Edge Functions, un contrôle de prix et une certification fournisseur.</p><button disabled={busy} onClick={()=>run(()=>q(supabase.rpc('admin_set_demo_mode_v8',{p_enabled:!active})))}>{active?'Désactiver le simulateur':'Activer le simulateur'}</button></div>
 <div className="card"><h3><Hotel size={19}/> Catalogue de démonstration</h3><p>Crée trois établissements fictifs, leurs catégories de chambre et des prix RO/BB pour 365 jours. Ils seront visibles dans la recherche agence, avec le tarif majoré.</p><button disabled={busy} className="primary" onClick={()=>run(()=>q(supabase.rpc('admin_seed_ratehawk_demo_v8')))}><RefreshCw size={16}/> Initialiser les hôtels fictifs</button><p className="muted">Relancer l'initialisation remplace les tarifs des trois hôtels de démonstration.</p></div></div>
 <div className="card"><h3>Établissements de test ({items.length})</h3>{items.map(h=><div className="fin-line" key={h.hotel_id}><div><b>{h.hotels?.name||'Hôtel'}</b><small>{h.provider_code} · {h.hotels?.city}</small></div><span className="pill">{h.hotels?.status||'Publié'}</span></div>)}</div>
 </section>;
}
