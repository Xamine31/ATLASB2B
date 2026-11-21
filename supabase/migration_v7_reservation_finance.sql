-- AtlasB2B V7 — migration additive à appliquer après V5 et V6.
-- Toutes les opérations monétaires restent des simulations, aucun transfert bancaire.
BEGIN;

ALTER TABLE public.booking_requests ADD COLUMN IF NOT EXISTS room_count integer NOT NULL DEFAULT 1;
ALTER TABLE public.booking_requests ADD COLUMN IF NOT EXISTS adults integer NOT NULL DEFAULT 2;
ALTER TABLE public.booking_requests ADD COLUMN IF NOT EXISTS children integer NOT NULL DEFAULT 0;
ALTER TABLE public.booking_requests ADD COLUMN IF NOT EXISTS price_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.booking_requests ADD CONSTRAINT booking_rooms_v7 CHECK(room_count BETWEEN 1 AND 5);
ALTER TABLE public.booking_requests ADD CONSTRAINT booking_occupants_v7 CHECK(adults BETWEEN 1 AND 20 AND children BETWEEN 0 AND 20);

CREATE TABLE IF NOT EXISTS public.booking_holds_v7 (
 booking_id uuid PRIMARY KEY REFERENCES public.booking_requests(id) ON DELETE RESTRICT,
 agency_id uuid NOT NULL REFERENCES public.agencies(id),
 amount_eur numeric(12,2) NOT NULL CHECK(amount_eur>0),
 state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','captured','released')),
 created_at timestamptz NOT NULL DEFAULT now(),
 finalized_at timestamptz
);
CREATE INDEX IF NOT EXISTS booking_holds_v7_agency_active_idx ON public.booking_holds_v7(agency_id) WHERE state='active';
CREATE UNIQUE INDEX IF NOT EXISTS supplier_payables_booking_v7_unique ON public.supplier_payables(booking_id) WHERE booking_id IS NOT NULL AND reference LIKE 'RES-%';
ALTER TABLE public.booking_holds_v7 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS booking_holds_v7_select ON public.booking_holds_v7;
CREATE POLICY booking_holds_v7_select ON public.booking_holds_v7 FOR SELECT TO authenticated USING (public.is_admin() OR (agency_id=public.my_agency() AND public.is_approved_agency()));
GRANT SELECT ON public.booking_holds_v7 TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.booking_holds_v7 FROM anon,authenticated;

CREATE OR REPLACE FUNCTION public.wallet_summary_v7(p_agency uuid DEFAULT NULL)
RETURNS TABLE(agency_id uuid, ledger_eur numeric, blocked_eur numeric, available_eur numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a uuid;
BEGIN
 a := CASE WHEN public.is_admin() THEN coalesce(p_agency, public.my_agency()) ELSE public.my_agency() END;
 IF a IS NULL OR (NOT public.is_admin() AND (a<>public.my_agency() OR NOT public.is_approved_agency())) THEN
  RAISE EXCEPTION 'Compte non autorisé';
 END IF;
 RETURN QUERY SELECT a,
  (SELECT coalesce(sum(e.amount_eur),0)::numeric FROM public.wallet_entries e WHERE e.agency_id=a),
  (SELECT coalesce(sum(b.amount_eur),0)::numeric FROM public.booking_holds_v7 b WHERE b.agency_id=a AND b.state='active'),
  ((SELECT coalesce(sum(e.amount_eur),0) FROM public.wallet_entries e WHERE e.agency_id=a)
   -(SELECT coalesce(sum(b.amount_eur),0) FROM public.booking_holds_v7 b WHERE b.agency_id=a AND b.state='active'))::numeric;
END $$;
REVOKE ALL ON FUNCTION public.wallet_summary_v7(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wallet_summary_v7(uuid) TO authenticated;

-- Une offre complète est un type de chambre + une pension, évalués sur toutes les nuits.
-- Les remises ne sont pas appliquées: le montant constitue le prix de base agence.
CREATE OR REPLACE FUNCTION public.hotel_options_v7(p_hotel uuid,p_checkin date,p_checkout date)
RETURNS TABLE(hotel_id uuid,room_name text,room_label text,room_description text,room_photo text,capacity integer,board text,total_price numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non approuvée'; END IF;
 IF p_checkin IS NULL OR p_checkout IS NULL OR p_checkin<current_date OR p_checkout<=p_checkin OR p_checkout>p_checkin+30 THEN
  RAISE EXCEPTION 'Dates de séjour invalides (maximum 30 nuits)'; END IF;
 RETURN QUERY
 SELECT h.id,rt.name,coalesce(nullif(rt.display_name,''),rt.name),rt.description,rt.photo_url,rt.capacity,r.board,
  round(sum(r.net_price)*(1+a.markup_percent/100),2)
 FROM public.hotels h
 JOIN public.room_types rt ON rt.hotel_id=h.id AND rt.is_public=true
 JOIN public.rates r ON r.hotel_id=h.id AND r.room_name=rt.name
 JOIN public.agencies a ON a.id=public.my_agency() AND a.approved=true
 JOIN LATERAL generate_series(p_checkin::timestamp,(p_checkout-1)::timestamp,interval '1 day') n(d) ON n.d::date BETWEEN r.date_start AND r.date_end
 WHERE h.id=p_hotel AND h.status='published'
 GROUP BY h.id,rt.id,r.board,a.markup_percent
 HAVING count(DISTINCT n.d::date)=(p_checkout-p_checkin)
 ORDER BY round(sum(r.net_price)*(1+a.markup_percent/100),2), rt.name, r.board;
END $$;
REVOKE ALL ON FUNCTION public.hotel_options_v7(uuid,date,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hotel_options_v7(uuid,date,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.hotel_search_v7(p_checkin date,p_checkout date,p_city text DEFAULT '',p_rooms integer DEFAULT 1,p_adults integer DEFAULT 2,p_children integer DEFAULT 0)
RETURNS TABLE(hotel_id uuid,hotel_name text,city text,country text,stars integer,cover_url text,description text,from_price numeric,options_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non approuvée'; END IF;
 IF p_rooms NOT BETWEEN 1 AND 5 OR p_adults NOT BETWEEN 1 AND 20 OR p_children NOT BETWEEN 0 AND 20 THEN RAISE EXCEPTION 'Voyageurs invalides'; END IF;
 IF p_checkin IS NULL OR p_checkout IS NULL OR p_checkin<current_date OR p_checkout<=p_checkin OR p_checkout>p_checkin+30 THEN
  RAISE EXCEPTION 'Dates de séjour invalides (maximum 30 nuits)'; END IF;
 RETURN QUERY
 SELECT h.id,h.name,h.city,h.country,h.stars,h.cover_url,h.description,min(o.total_price*p_rooms),count(*)
 FROM public.hotels h
 CROSS JOIN LATERAL public.hotel_options_v7(h.id,p_checkin,p_checkout) o
 WHERE h.status='published' AND o.capacity*p_rooms >= p_adults+p_children AND (trim(coalesce(p_city,''))='' OR h.name ILIKE '%'||trim(p_city)||'%' OR h.city ILIKE '%'||trim(p_city)||'%' OR h.country ILIKE '%'||trim(p_city)||'%')
 GROUP BY h.id ORDER BY min(o.total_price*p_rooms),h.name;
END $$;
REVOKE ALL ON FUNCTION public.hotel_search_v7(date,date,text,integer,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hotel_search_v7(date,date,text,integer,integer,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_booking_v7(
 p_hotel uuid,p_room text,p_board text,p_checkin date,p_checkout date,p_guest text,
 p_room_count integer DEFAULT 1,p_adults integer DEFAULT 2,p_children integer DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a uuid; priced numeric; raw_price numeric; available numeric; needed numeric; ident uuid; cap integer; markup numeric;
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non approuvée'; END IF;
 a:=public.my_agency();
 IF p_room_count NOT BETWEEN 1 AND 5 OR p_adults NOT BETWEEN 1 AND 20 OR p_children NOT BETWEEN 0 AND 20 THEN RAISE EXCEPTION 'Composition invalide'; END IF;
 IF length(trim(coalesce(p_guest,'')))<3 THEN RAISE EXCEPTION 'Nom du voyageur requis'; END IF;
 IF p_checkin IS NULL OR p_checkout IS NULL OR p_checkin<current_date OR p_checkout<=p_checkin OR p_checkout>p_checkin+30 THEN RAISE EXCEPTION 'Dates invalides'; END IF;
 -- Verrou unique par agence: deux demandes simultanées ne peuvent pas dépenser le même solde.
 SELECT ag.markup_percent INTO markup FROM public.agencies ag WHERE ag.id=a AND ag.approved=true FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Agence non active'; END IF;
 SELECT rt.capacity INTO cap FROM public.room_types rt JOIN public.hotels h ON h.id=rt.hotel_id
 WHERE h.id=p_hotel AND h.status='published' AND rt.name=p_room AND rt.is_public=true;
 IF cap IS NULL THEN RAISE EXCEPTION 'Chambre non disponible'; END IF;
 IF p_adults+p_children>cap*p_room_count THEN RAISE EXCEPTION 'Capacité dépassée pour cette catégorie de chambre'; END IF;
 SELECT opt.total_price INTO priced FROM public.hotel_options_v7(p_hotel,p_checkin,p_checkout) opt
 WHERE opt.room_name=p_room AND opt.board=p_board LIMIT 1;
 IF priced IS NULL THEN RAISE EXCEPTION 'Aucun tarif pour cette offre et ces dates'; END IF;
 SELECT sum(r.net_price) INTO raw_price
 FROM public.rates r JOIN LATERAL generate_series(p_checkin::timestamp,(p_checkout-1)::timestamp,interval '1 day') n(d)
 ON n.d::date BETWEEN r.date_start AND r.date_end
 WHERE r.hotel_id=p_hotel AND r.room_name=p_room AND r.board=p_board;
 IF raw_price IS NULL OR raw_price<=0 THEN RAISE EXCEPTION 'Tarif fournisseur non valide'; END IF;
 needed:=round(priced*p_room_count,2);
 SELECT coalesce(sum(e.amount_eur),0) - (SELECT coalesce(sum(b.amount_eur),0) FROM public.booking_holds_v7 b WHERE b.agency_id=a AND b.state='active')
 INTO available FROM public.wallet_entries e WHERE e.agency_id=a;
 IF available<needed THEN RAISE EXCEPTION 'Crédit insuffisant : disponible % €, séjour % €',round(available,2),needed; END IF;
 INSERT INTO public.booking_requests(agency_id,hotel_id,room_name,board,checkin,checkout,guest_name,total_eur,net_total_eur,room_count,adults,children,price_snapshot)
 VALUES(a,p_hotel,p_room,p_board,p_checkin,p_checkout,trim(p_guest),needed,round(raw_price*p_room_count,2),p_room_count,p_adults,p_children,
 jsonb_build_object('base_total_eur',needed,'net_total_eur',round(raw_price*p_room_count,2),'markup_percent',markup,'promotion_applied',false,'currency','EUR','rooms',p_room_count,'adults',p_adults,'children',p_children)) RETURNING id INTO ident;
 INSERT INTO public.booking_holds_v7(booking_id,agency_id,amount_eur) VALUES(ident,a,needed);
 INSERT INTO public.finance_audit(event,entity_id,details) VALUES('booking_held_v7',ident,jsonb_build_object('agency_id',a,'amount_eur',needed));
 RETURN ident;
END $$;
REVOKE ALL ON FUNCTION public.submit_booking_v7(uuid,text,text,date,date,text,integer,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_booking_v7(uuid,text,text,date,date,text,integer,integer,integer) TO authenticated;
-- Le point d'entrée historique doit être désactivé pour éviter une réservation sans blocage.
REVOKE EXECUTE ON FUNCTION public.submit_booking(uuid,text,text,date,date,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.admin_booking_status(p_booking uuid,p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b public.booking_requests; hold public.booking_holds_v7; hn text; dn text; payee_type text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrateur requis'; END IF;
 IF p_status NOT IN ('confirmed','rejected') THEN RAISE EXCEPTION 'Statut non autorisé'; END IF;
 SELECT * INTO b FROM public.booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR b.status<>'pending' THEN RAISE EXCEPTION 'Demande inexistante ou déjà traitée'; END IF;
 -- Anciennes demandes V6 ne peuvent pas être confirmées par erreur sans blocage financier.
 SELECT * INTO hold FROM public.booking_holds_v7 WHERE booking_id=p_booking FOR UPDATE;
 IF NOT FOUND OR hold.state<>'active' OR hold.amount_eur<>b.total_eur THEN RAISE EXCEPTION 'Blocage financier V7 manquant ou invalide'; END IF;
 PERFORM 1 FROM public.agencies WHERE id=b.agency_id FOR UPDATE;
 IF p_status='confirmed' THEN
  INSERT INTO public.wallet_entries(agency_id,amount_eur,entry_type,note,booking_id)
  VALUES(b.agency_id,-b.total_eur,'booking_debit','Débit après confirmation de la réservation '||b.id,b.id);
  UPDATE public.booking_holds_v7 SET state='captured',finalized_at=now() WHERE booking_id=p_booking;
  SELECT h.name,d.name INTO hn,dn FROM public.hotels h LEFT JOIN public.dmcs d ON d.id=h.dmc_id WHERE h.id=b.hotel_id;
  payee_type:=CASE WHEN dn IS NULL THEN 'hotel' ELSE 'dmc' END;
  INSERT INTO public.supplier_payables(beneficiary_name,beneficiary_type,booking_id,amount_eur,reference,status)
  VALUES(coalesce(dn,hn,'Hôtel contracté'),payee_type,b.id,b.net_total_eur,'RES-'||left(b.id::text,8),'draft');
 ELSE
  UPDATE public.booking_holds_v7 SET state='released',finalized_at=now() WHERE booking_id=p_booking;
 END IF;
 UPDATE public.booking_requests SET status=p_status WHERE id=p_booking;
 INSERT INTO public.finance_audit(event,entity_id,details) VALUES('booking_'||p_status||'_v7',p_booking,
 jsonb_build_object('amount_eur',b.total_eur,'supplier_eur',b.net_total_eur,'agency_id',b.agency_id));
END $$;
REVOKE ALL ON FUNCTION public.admin_booking_status(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_booking_status(uuid,text) TO authenticated;

-- Empêche les débits manuels contournant le cycle V7 et les ajustements utilisant du crédit bloqué.
CREATE OR REPLACE FUNCTION public.admin_wallet_entry(p_agency uuid,p_amount numeric,p_kind text,p_note text,p_booking uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE balance numeric; blocked numeric; refunded numeric; b public.booking_requests; ident uuid;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrateur requis'; END IF;
 IF p_kind NOT IN ('manual_adjustment','refund') THEN RAISE EXCEPTION 'Débit des réservations uniquement par confirmation administrateur'; END IF;
 IF p_amount IS NULL OR p_amount=0 OR p_amount<>round(p_amount,2) OR abs(p_amount)>1000000 OR length(trim(coalesce(p_note,'')))<4 THEN RAISE EXCEPTION 'Montant ou motif invalide'; END IF;
 IF (p_kind='refund' AND (p_amount<=0 OR p_booking IS NULL)) OR (p_kind='manual_adjustment' AND p_booking IS NOT NULL) THEN RAISE EXCEPTION 'Référence invalide'; END IF;
 PERFORM 1 FROM public.agencies WHERE id=p_agency FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Agence introuvable'; END IF;
 IF p_kind='refund' THEN
  SELECT * INTO b FROM public.booking_requests WHERE id=p_booking;
  IF NOT FOUND OR b.agency_id<>p_agency OR b.status<>'confirmed' THEN RAISE EXCEPTION 'Réservation non confirmée'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.wallet_entries WHERE booking_id=p_booking AND entry_type='booking_debit') THEN RAISE EXCEPTION 'Débit initial introuvable'; END IF;
  SELECT coalesce(sum(e.amount_eur),0) INTO refunded FROM public.wallet_entries e WHERE e.booking_id=p_booking AND e.entry_type='refund';
  IF refunded+p_amount>b.total_eur THEN RAISE EXCEPTION 'Remboursement supérieur au débit'; END IF;
 END IF;
 SELECT coalesce(sum(e.amount_eur),0) INTO balance FROM public.wallet_entries e WHERE e.agency_id=p_agency;
 SELECT coalesce(sum(h.amount_eur),0) INTO blocked FROM public.booking_holds_v7 h WHERE h.agency_id=p_agency AND h.state='active';
 IF balance+p_amount<blocked THEN RAISE EXCEPTION 'Opération refusée : montant bloqué sur des réservations'; END IF;
 INSERT INTO public.wallet_entries(agency_id,amount_eur,entry_type,note,booking_id)
 VALUES(p_agency,p_amount,p_kind,trim(p_note),p_booking) RETURNING id INTO ident;
 INSERT INTO public.finance_audit(event,entity_id,details) VALUES('wallet_adjustment_v7',ident,jsonb_build_object('kind',p_kind,'amount',p_amount,'agency_id',p_agency));
 RETURN ident;
END $$;
REVOKE ALL ON FUNCTION public.admin_wallet_entry(uuid,numeric,text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_wallet_entry(uuid,numeric,text,text,uuid) TO authenticated;

-- Les paiements liés aux dossiers sont produits à la confirmation : pas de deuxième création manuelle.
CREATE OR REPLACE FUNCTION public.admin_create_payable(p_beneficiary text,p_type text,p_amount numeric,p_reference text,p_due date DEFAULT NULL,p_booking uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE ident uuid;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrateur requis'; END IF;
 IF p_booking IS NOT NULL THEN RAISE EXCEPTION 'Règlement dossier créé automatiquement à la confirmation'; END IF;
 IF p_type NOT IN ('dmc','hotel','api') OR length(trim(coalesce(p_beneficiary,'')))<3 OR length(trim(coalesce(p_reference,'')))<3 OR p_amount<=0 OR p_amount<>round(p_amount,2) THEN RAISE EXCEPTION 'Règlement invalide'; END IF;
 INSERT INTO public.supplier_payables(beneficiary_name,beneficiary_type,amount_eur,reference,due_date)
 VALUES(trim(p_beneficiary),p_type,p_amount,trim(p_reference),p_due) RETURNING id INTO ident;
 INSERT INTO public.finance_audit(event,entity_id) VALUES('payable_created',ident);
 RETURN ident;
END $$;
REVOKE ALL ON FUNCTION public.admin_create_payable(text,text,numeric,text,date,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_payable(text,text,numeric,text,date,uuid) TO authenticated;
COMMIT;
