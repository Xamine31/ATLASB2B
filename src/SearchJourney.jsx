import React,{useEffect,useMemo,useState} from 'react';
import {ArrowLeft,ArrowRight,CalendarDays,CheckCircle2,ChevronRight,Hotel,MapPin,Search,ShieldCheck,SlidersHorizontal,Sparkles,Users,Wallet} from 'lucide-react';
import {supabase,euro} from './supabase';
const unpack=async op=>{const {data,error}=await op;if(error)throw Error(error.message);return data||[]};
const nextDate=(days)=>{const d=new Date();d.setHours(12,0,0,0);d.setDate(d.getDate()+days);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`};
const dayDiff=(from,to)=>Math.round((new Date(to+'T12:00:00')-new Date(from+'T12:00:00'))/86400000);
const BOARD_NAMES={'RO':'Hébergement seul','BB':'Petit-déjeuner inclus','HB':'Demi-pension','FB':'Pension complète','ALL IN':'Tout compris'};
const money=n=>euro(Number(n||0));

export default function SearchJourney({notify,fail}){
 const [query,setQuery]=useState(''),[checkin,setCheckin]=useState(nextDate(4)),[checkout,setCheckout]=useState(nextDate(7)),[adults,setAdults]=useState(2),[children,setChildren]=useState(0),[rooms,setRooms]=useState(1);
 const [results,setResults]=useState([]),[selected,setSelected]=useState(null),[options,setOptions]=useState([]),[promos,setPromos]=useState([]),[chosen,setChosen]=useState(''),[guest,setGuest]=useState('');
 const [guestEmail,setGuestEmail]=useState(''),[guestPhone,setGuestPhone]=useState(''),[nationality,setNationality]=useState(''),[specialRequests,setSpecialRequests]=useState(''),[acceptTerms,setAcceptTerms]=useState(false);
 const [demoHotels,setDemoHotels]=useState([]),[demoOutcome,setDemoOutcome]=useState('confirmed');
 useEffect(()=>{supabase.from('demo_ratehawk_hotels_v8').select('hotel_id').then(({data,error})=>{if(!error)setDemoHotels((data||[]).map(x=>x.hotel_id))})},[]);
 const selectedMock=selected&&demoHotels.includes(selected.hotel_id);
 const [busy,setBusy]=useState(false),[searched,setSearched]=useState(false),[verifiedDates,setVerifiedDates]=useState(null),[term,setTerm]=useState('');
 const nights=dayDiff(checkin,checkout);
 const available=options.filter(o=>(o.capacity||2)*rooms>=adults+children);
 const choice=available.find(o=>o.room_name+'|'+o.board===chosen)||available[0];
 const total=choice?Number(choice.total_price)*rooms:0;
 const searchHotels=async(e)=>{
  e?.preventDefault?.();
  if(nights<1||nights>30){fail(Error('Sélectionne un séjour de 1 à 30 nuits.'));return}
  setBusy(true);setSelected(null);setChosen('');setOptions([]);setPromos([]);
  try{const data=await unpack(supabase.rpc('hotel_search_v7',{p_checkin:checkin,p_checkout:checkout,p_city:query,p_rooms:rooms,p_adults:adults,p_children:children}));setResults(data);setSearched(true);setVerifiedDates(`${checkin}|${checkout}`);setTerm(query)}
  catch(ex){setResults([]);fail(ex)}finally{setBusy(false)}
 };
 const openHotel=async(h)=>{
  setBusy(true);
  try{
   const [opts,pr]=await Promise.all([
    unpack(supabase.rpc('hotel_options_v7',{p_hotel:h.hotel_id,p_checkin:checkin,p_checkout:checkout})),
    unpack(supabase.from('hotel_promotions').select('code,label,description,discount_percent').eq('hotel_id',h.hotel_id).eq('is_public',true))
   ]);
   setOptions(opts);setPromos(pr);setChosen('');setSelected(h);window.scrollTo({top:0,behavior:'smooth'});
  }catch(ex){fail(ex)}finally{setBusy(false)}
 };
 const request=async(e)=>{
  e.preventDefault();if(!choice||!selected)return;
  if(!guest.trim()||guest.trim().length<3||!guestEmail.includes('@')||guestPhone.trim().length<5||nationality.trim().length<2||!acceptTerms){fail(Error('Complète les coordonnées voyageurs et accepte les conditions avant de poursuivre.'));return}
  setBusy(true);
  try{
   const bookingId=await unpack(supabase.rpc('submit_booking_with_guests_v8',{p_hotel:selected.hotel_id,p_room:choice.room_name,p_board:choice.board,p_checkin:checkin,p_checkout:checkout,p_guest:guest.trim(),p_room_count:rooms,p_adults:adults,p_children:children,p_email:guestEmail.trim(),p_phone:guestPhone.trim(),p_nationality:nationality.trim(),p_special:specialRequests.trim(),p_guests:[{name:guest.trim()}]}));
   if(selectedMock){try{await unpack(supabase.rpc('demo_ratehawk_resolve_v8',{p_booking:bookingId,p_outcome:demoOutcome}));notify(demoOutcome==='confirmed'?'Réservation fournisseur simulée confirmée. Crédit débité et dette fournisseur créée.':demoOutcome==='rejected'?'Refus fournisseur simulé. Crédit libéré.':'Fournisseur simulé sans réponse : crédit conservé en blocage.')}catch(e){notify('Demande créée avec montant bloqué. Simulation fournisseur incomplète : vérifie le dossier et contacte l’administrateur.')}}
   else notify('Demande enregistrée. Crédit bloqué jusqu’à validation ou refus. Consultez Mes réservations et Mon crédit.');
   setSelected(null);setResults([]);setSearched(false);setGuest('');setGuestEmail('');setGuestPhone('');setNationality('');setSpecialRequests('');setAcceptTerms(false);
  }catch(ex){fail(ex)}finally{setBusy(false)}
 };
 const changeDates=async(e)=>{e.preventDefault();await searchHotels()};
 return <div className="v7-journey">
  <div className="v7-intro"><div><span className="eyebrow">SÉLECTION HÔTELIÈRE · ESPACE AGENCE</span><h2>Votre prochaine destination.</h2><p>Découvrez les établissements disponibles, puis composez le séjour idéal pour votre client.</p></div><div className="v7-intro-icon"><Hotel size={34}/></div></div>
  <form className="v7-searchbar" onSubmit={changeDates}>
   <label><span><MapPin size={14}/> Destination ou hôtel</span><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Ville, pays, établissement"/></label>
   <label><span><CalendarDays size={14}/> Arrivée</span><input type="date" min={nextDate(0)} value={checkin} required onChange={e=>{setCheckin(e.target.value);if(e.target.value>=checkout)setCheckout(nextDate(8))}}/></label>
   <label><span><CalendarDays size={14}/> Départ</span><input type="date" min={checkin} value={checkout} required onChange={e=>setCheckout(e.target.value)}/></label>
   <button className="primary" disabled={busy}><Search size={17}/>{busy?'Recherche…':'Rechercher'}</button>
  </form>
  {selected&&verifiedDates!==`${checkin}|${checkout}`&&<div className="alert info">Les dates ont changé. Lancez une nouvelle recherche pour recalculer les tarifs.</div>}
  {!selected? <>
   <div className="v7-list-head"><div><h3>{!searched?'Une sélection pensée pour les professionnels':`${results.length} établissement${results.length>1?'s':''} trouvé${results.length>1?'s':''}`}</h3><p>{searched?`${term||'Toutes destinations'} · ${nights} nuit${nights>1?'s':''} · Prix total du séjour · hors promotions`:'Recherchez une destination et consultez le prix le plus compétitif par hôtel.'}</p></div><span className="v7-small-pill"><SlidersHorizontal size={14}/> Tarifs professionnels</span></div>
   {searched&&!results.length&&<div className="card v7-empty"><Search size={34}/><h3>Aucun hôtel disponible pour ces critères</h3><p>Vérifiez les dates et les tarifs publiés, ou recherchez une autre destination.</p></div>}
   <div className="v7-hotel-list">{results.map(h=><article className="v7-hotel-card" key={h.hotel_id}><div className="v7-hotel-photo">{h.cover_url?<img src={h.cover_url} alt={h.hotel_name}/>:<div className="v7-no-photo"><Hotel size={36}/><span>NETBEDS</span></div>}</div><div className="v7-hotel-description">{demoHotels.includes(h.hotel_id)&&<span className="pill">Fournisseur simulé · données fictives</span>}<div className="v7-stars">{'★'.repeat(Math.min(5,h.stars||3))}</div><h3>{h.hotel_name}</h3><p className="v7-location"><MapPin size={14}/>{h.city}, {h.country}</p><p className="v7-desc">{h.description||'Découvrez cet établissement et ses différentes formules de séjour.'}</p><span className="v7-small-pill">{h.options_count} option{Number(h.options_count)>1?'s':''} tarifaire{Number(h.options_count)>1?'s':''}</span></div><div className="v7-hotel-price"><small>À partir de</small><strong>{money(h.from_price)}</strong><span>Pour {nights} nuit{nights>1?'s':''} · {rooms} chambre{rooms>1?'s':''}</span><span>Hors promotions · sous réserve de confirmation</span><button className="primary" disabled={busy} onClick={()=>openHotel(h)}>Voir les offres <ChevronRight size={17}/></button></div></article>)}</div>
  </>:<>
   <button className="v7-back" onClick={()=>{setSelected(null);setChosen('')}}><ArrowLeft size={16}/> Tous les hôtels</button>
   <div className="v7-detail-hero"><div className="v7-detail-cover">{selected.cover_url?<img src={selected.cover_url} alt={selected.hotel_name}/>:<div className="v7-no-photo"><Hotel size={42}/></div>}</div><div className="v7-detail-title"><div className="v7-stars">{'★'.repeat(Math.min(5,selected.stars||3))}</div><h2>{selected.hotel_name}</h2><p><MapPin size={16}/>{selected.city}, {selected.country}</p><p>{selected.description||'Choisissez votre catégorie de chambre et votre formule pour obtenir le tarif exact.'}</p></div></div>
   <div className="v7-config-head"><div><span className="eyebrow">CONFIGURATION DE SÉJOUR</span><h3>Composez votre séjour</h3></div><span className="v7-small-pill"><ShieldCheck size={15}/> Tarif recalculé avant demande</span></div>
   <div className="v7-config-layout"><div className="v7-config-main">
    <div className="card v7-card"><h3><Users size={19}/> Voyageurs et chambres</h3><div className="v7-field-grid"><label>Chambres<select value={rooms} onChange={e=>setRooms(Number(e.target.value))}>{[1,2,3,4,5].map(x=><option key={x} value={x}>{x}</option>)}</select></label><label>Adultes<select value={adults} onChange={e=>setAdults(Number(e.target.value))}>{Array.from({length:20},(_,i)=>i+1).map(x=><option key={x} value={x}>{x}</option>)}</select></label><label>Enfants<select value={children} onChange={e=>setChildren(Number(e.target.value))}>{Array.from({length:21},(_,i)=>i).map(x=><option key={x} value={x}>{x}</option>)}</select></label></div><p className="v7-help">La capacité totale doit couvrir tous les voyageurs. Les réductions enfants et autres promotions seront calculées uniquement lorsqu'une règle tarifaire validée sera disponible.</p></div>
    <div className="card v7-card"><h3><SlidersHorizontal size={19}/> Chambre et pension</h3><p>Le prix tient compte des dates, de la catégorie, de la pension, du nombre de chambres et de la majoration de votre agence.</p>{available.length? <div className="v7-options">{available.map(o=>{const key=o.room_name+'|'+o.board;const active=(choice?.room_name+'|'+choice?.board)===key;return <button type="button" key={key} className={'v7-option '+(active?'selected':'')} onClick={()=>setChosen(key)}><div className="v7-option-img">{o.room_photo?<img src={o.room_photo} alt={o.room_label}/>:<Hotel size={21}/>}</div><span className="v7-option-name"><b>{o.room_label}</b><small>{BOARD_NAMES[o.board]||o.board} · jusqu'à {o.capacity} personnes / chambre</small>{o.room_description&&<small>{o.room_description}</small>}</span><span className="v7-option-money"><b>{money(Number(o.total_price)*rooms)}</b><small>Total séjour</small></span><span className="v7-radio">{active?<CheckCircle2 size={21}/>:<span/>}</span></button>})}</div>:<div className="alert info">Aucune catégorie n'accueille la composition demandée. Modifiez le nombre de chambres ou de voyageurs.</div>}</div>
    {promos.length>0&&<div className="card v7-card"><h3><Sparkles size={19}/> Avantages et promotions</h3><div className="v7-promo-grid">{promos.map(p=><div className="v7-promo" key={p.code}><b>{p.label}</b><small>{p.description||`Réduction annoncée : ${p.discount_percent}%`}</small></div>)}</div><p className="v7-help">Promotions présentées à titre informatif, non déduites automatiquement des tarifs de base.</p></div>}
   </div><aside className="v7-config-side"><div className="card v7-recap"><span className="eyebrow">RÉCAPITULATIF</span><h3>Votre proposition</h3><div className="v7-recap-line"><span>Séjour</span><b>{nights} nuits</b></div><div className="v7-recap-line"><span>Chambres</span><b>{rooms}</b></div><div className="v7-recap-line"><span>Voyageurs</span><b>{adults} adultes · {children} enfants</b></div><div className="v7-recap-line"><span>Catégorie</span><b>{choice?.room_label||'—'}</b></div><div className="v7-recap-line"><span>Pension</span><b>{choice?BOARD_NAMES[choice.board]:'—'}</b></div>{selectedMock&&<div className="v7-mock"><span className="eyebrow">SCÉNARIO RATEHAWK SIMULÉ</span><p>Aucune réservation réelle chez RateHawk. Choisis la réponse de test.</p><select value={demoOutcome} onChange={e=>setDemoOutcome(e.target.value)}><option value="confirmed">Confirmation simulée</option><option value="rejected">Refus simulé</option><option value="pending">En attente simulée</option></select></div>}<div className="v7-recap-total"><span>Tarif total de base</span><strong>{choice?money(total):'—'}</strong><small>Hors promotions · prix du séjour</small></div><form onSubmit={request}><label>Nom du voyageur principal<input value={guest} required minLength={3} onChange={e=>setGuest(e.target.value)} placeholder="Prénom Nom"/></label><label>Email du passager<input type="email" required value={guestEmail} onChange={e=>setGuestEmail(e.target.value)} placeholder="client@exemple.fr"/></label><label>Téléphone du passager<input required minLength={5} value={guestPhone} onChange={e=>setGuestPhone(e.target.value)} placeholder="+33…"/></label><label>Nationalité / résidence<input required minLength={2} value={nationality} onChange={e=>setNationality(e.target.value)} placeholder="France"/></label><label>Demandes spéciales<textarea rows={2} value={specialRequests} onChange={e=>setSpecialRequests(e.target.value)} placeholder="Arrivée tardive, préférences…"/></label><label className="switchline"><input type="checkbox" required checked={acceptTerms} onChange={e=>setAcceptTerms(e.target.checked)}/>Je confirme les coordonnées et accepte que la demande soit soumise aux conditions du fournisseur.</label><button className="primary" disabled={busy||!choice||!acceptTerms||verifiedDates!==`${checkin}|${checkout}`}>{busy?'Validation…':'Envoyer la demande'} <ArrowRight size={16}/></button></form><div className="v7-hold-note"><Wallet size={17}/><span>Le montant est bloqué sur le crédit disponible, puis débité uniquement après confirmation par l'administration. En cas de refus, il est libéré.</span></div><small className="v7-demo-foot">Environnement de démonstration : aucune réservation fournisseur ni opération bancaire réelle.</small></div></aside></div>
  </>}
 </div>
}
