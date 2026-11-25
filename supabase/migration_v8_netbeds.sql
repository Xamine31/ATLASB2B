-- Netbeds V8. Apply ONLY after successful V5, V6 and V7 migrations to a backed-up test database.
-- Commercial, wallet and simulated provider operations do not move real funds.
BEGIN;
ALTER TABLE public.agencies ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'EUR';
ALTER TABLE public.agencies ADD COLUMN IF NOT EXISTS credit_alert_eur numeric(12,2) NOT NULL DEFAULT 500 CHECK (credit_alert_eur>=0);
ALTER TABLE public.agencies ADD COLUMN IF NOT EXISTS logo_url text;
ALTER TABLE public.agencies ADD COLUMN IF NOT EXISTS notes text NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS public.agency_hotel_markups (
 agency_id uuid NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
 hotel_id uuid NOT NULL REFERENCES public.hotels(id) ON DELETE CASCADE,
 markup_percent numeric(6,2) NOT NULL CHECK(markup_percent BETWEEN 0 AND 100),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(agency_id,hotel_id)
);
ALTER TABLE public.agency_hotel_markups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS agency_hotel_markups_admin ON public.agency_hotel_markups;
CREATE POLICY agency_hotel_markups_admin ON public.agency_hotel_markups FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
REVOKE ALL ON public.agency_hotel_markups FROM anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.agency_hotel_markups TO authenticated;

CREATE TABLE IF NOT EXISTS public.hotel_contracts_v8 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 hotel_id uuid NOT NULL REFERENCES public.hotels(id) ON DELETE CASCADE,
 reference text NOT NULL UNIQUE,
 supplier_name text NOT NULL,
 source_type text NOT NULL DEFAULT 'direct' CHECK(source_type IN ('direct','dmc','api')),
 currency text NOT NULL DEFAULT 'EUR',
 valid_from date NOT NULL,
 valid_to date NOT NULL CHECK(valid_to>=valid_from),
 payment_terms text NOT NULL DEFAULT '',
 cancellation_terms text NOT NULL DEFAULT '',
 notes text NOT NULL DEFAULT '',
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','approved','published','suspended','archived')),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
DROP POLICY IF EXISTS hotel_contracts_v8_dmc_insert ON public.hotel_contracts_v8;
CREATE INDEX IF NOT EXISTS hotel_contracts_v8_hotel_idx ON public.hotel_contracts_v8(hotel_id);
ALTER TABLE public.hotel_contracts_v8 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hotel_contracts_v8_admin_all ON public.hotel_contracts_v8;
CREATE POLICY hotel_contracts_v8_admin_all ON public.hotel_contracts_v8 FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
DROP POLICY IF EXISTS hotel_contracts_v8_dmc_read ON public.hotel_contracts_v8;
CREATE POLICY hotel_contracts_v8_dmc_read ON public.hotel_contracts_v8 FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND h.dmc_id=public.my_dmc()));
CREATE POLICY hotel_contracts_v8_dmc_insert ON public.hotel_contracts_v8 FOR INSERT TO authenticated
 WITH CHECK(status='draft' AND source_type='dmc' AND EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND h.dmc_id=public.my_dmc()));
CREATE POLICY hotel_contracts_v8_dmc_update ON public.hotel_contracts_v8 FOR UPDATE TO authenticated
 USING(status='draft' AND source_type='dmc' AND EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND h.dmc_id=public.my_dmc()))
 WITH CHECK(status='draft' AND source_type='dmc' AND EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND h.dmc_id=public.my_dmc()));
GRANT SELECT,INSERT,UPDATE,DELETE ON public.hotel_contracts_v8 TO authenticated;

CREATE TABLE IF NOT EXISTS public.netbeds_demo_settings_v8 (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 enabled boolean NOT NULL DEFAULT true
);
INSERT INTO public.netbeds_demo_settings_v8(id,enabled) VALUES(true,true) ON CONFLICT(id) DO NOTHING;
ALTER TABLE public.netbeds_demo_settings_v8 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS netbeds_demo_admin_v8 ON public.netbeds_demo_settings_v8;
CREATE POLICY netbeds_demo_admin_v8 ON public.netbeds_demo_settings_v8 FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
GRANT SELECT,UPDATE ON public.netbeds_demo_settings_v8 TO authenticated;

CREATE TABLE IF NOT EXISTS public.demo_ratehawk_hotels_v8 (
 hotel_id uuid PRIMARY KEY REFERENCES public.hotels(id) ON DELETE CASCADE,
 provider_code text NOT NULL UNIQUE,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.demo_ratehawk_hotels_v8 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_ratehawk_read_v8 ON public.demo_ratehawk_hotels_v8;
CREATE POLICY demo_ratehawk_read_v8 ON public.demo_ratehawk_hotels_v8 FOR SELECT TO authenticated USING(public.is_admin() OR public.is_approved_agency());
GRANT SELECT ON public.demo_ratehawk_hotels_v8 TO authenticated;

CREATE TABLE IF NOT EXISTS public.demo_ratehawk_bookings_v8 (
 booking_id uuid PRIMARY KEY REFERENCES public.booking_requests(id) ON DELETE CASCADE,
 supplier_reference text UNIQUE,
 outcome text NOT NULL CHECK(outcome IN ('confirmed','rejected','pending')),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.demo_ratehawk_bookings_v8 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_ratehawk_bookings_read_v8 ON public.demo_ratehawk_bookings_v8;
CREATE POLICY demo_ratehawk_bookings_read_v8 ON public.demo_ratehawk_bookings_v8 FOR SELECT TO authenticated USING (public.is_admin() OR EXISTS(SELECT 1 FROM public.booking_requests b WHERE b.id=booking_id AND b.agency_id=public.my_agency()));
GRANT SELECT ON public.demo_ratehawk_bookings_v8 TO authenticated;

-- Agency-specific hotel markup is applied inside the trusted SQL price calculation.
CREATE OR REPLACE FUNCTION public.hotel_options_v7(p_hotel uuid,p_checkin date,p_checkout date)
RETURNS TABLE(hotel_id uuid,room_name text,room_label text,room_description text,room_photo text,capacity integer,board text,total_price numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non approuvée'; END IF;
 IF p_checkin IS NULL OR p_checkout IS NULL OR p_checkin<current_date OR p_checkout<=p_checkin OR p_checkout>p_checkin+30 THEN RAISE EXCEPTION 'Dates invalides'; END IF;
 RETURN QUERY
 SELECT h.id,rt.name,coalesce(nullif(rt.display_name,''),rt.name),rt.description,rt.photo_url,rt.capacity,r.board,
 round(sum(r.net_price)*(1+coalesce(m.markup_percent,a.markup_percent)/100),2)
 FROM public.hotels h
 JOIN public.room_types rt ON rt.hotel_id=h.id AND rt.is_public=true
 JOIN public.rates r ON r.hotel_id=h.id AND r.room_name=rt.name
 JOIN public.agencies a ON a.id=public.my_agency() AND a.approved=true
 LEFT JOIN public.agency_hotel_markups m ON m.agency_id=a.id AND m.hotel_id=h.id
 JOIN LATERAL generate_series(p_checkin::timestamp,(p_checkout-1)::timestamp,interval '1 day') n(d) ON n.d::date BETWEEN r.date_start AND r.date_end
 WHERE h.id=p_hotel AND h.status='published'
 GROUP BY h.id,rt.id,r.board,a.markup_percent,m.markup_percent
 HAVING count(DISTINCT n.d::date)=(p_checkout-p_checkin)
 ORDER BY round(sum(r.net_price)*(1+coalesce(m.markup_percent,a.markup_percent)/100),2),rt.name,r.board;
END $$;
REVOKE ALL ON FUNCTION public.hotel_options_v7(uuid,date,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hotel_options_v7(uuid,date,date) TO authenticated;

-- Critical: submit_booking_v7 still calculates its amount from hotel_options_v7, so the override automatically affects locked agency prices.
-- Its price_snapshot.markup_percent is informational only and reports the default markup; monetary values are derived from the effective offer.
CREATE OR REPLACE FUNCTION public.admin_set_hotel_markup_v8(p_agency uuid,p_hotel uuid,p_markup numeric DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrateur requis'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.agencies WHERE id=p_agency) OR NOT EXISTS(SELECT 1 FROM public.hotels WHERE id=p_hotel) THEN RAISE EXCEPTION 'Agence ou hôtel introuvable'; END IF;
 IF p_markup IS NULL THEN DELETE FROM public.agency_hotel_markups WHERE agency_id=p_agency AND hotel_id=p_hotel;
 ELSE
  IF p_markup<0 OR p_markup>100 THEN RAISE EXCEPTION 'Marge hors limites'; END IF;
  INSERT INTO public.agency_hotel_markups(agency_id,hotel_id,markup_percent) VALUES(p_agency,p_hotel,p_markup)
   ON CONFLICT(agency_id,hotel_id) DO UPDATE SET markup_percent=excluded.markup_percent,updated_at=now();
 END IF;
 INSERT INTO public.finance_audit(event,details) VALUES('hotel_markup_v8',jsonb_build_object('agency_id',p_agency,'hotel_id',p_hotel,'markup',p_markup));
END $$;
REVOKE ALL ON FUNCTION public.admin_set_hotel_markup_v8(uuid,uuid,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_hotel_markup_v8(uuid,uuid,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_contract_status_v8(p_contract uuid,p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE old_status text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrateur requis'; END IF;
 SELECT status INTO old_status FROM public.hotel_contracts_v8 WHERE id=p_contract FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Contrat introuvable'; END IF;
 IF NOT ((old_status='draft' AND p_status='approved') OR (old_status='approved' AND p_status='published') OR (old_status='published' AND p_status='suspended') OR (old_status='suspended' AND p_status='published') OR (p_status='archived' AND old_status <> 'archived')) THEN RAISE EXCEPTION 'Transition de contrat invalide'; END IF;
 UPDATE public.hotel_contracts_v8 SET status=p_status,version=version+1,updated_at=now() WHERE id=p_contract;
 INSERT INTO public.finance_audit(event,entity_id,details) VALUES('contract_status_v8',p_contract,jsonb_build_object('before',old_status,'after',p_status));
END $$;
REVOKE ALL ON FUNCTION public.admin_contract_status_v8(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_contract_status_v8(uuid,text) TO authenticated;

-- Populate mock supplier hotels. This never talks to RateHawk and must never be confused with its real catalog.
CREATE OR REPLACE FUNCTION public.admin_seed_ratehawk_demo_v8()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_hotel uuid; current_from date; current_to date; entry record; added integer:=0;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrateur requis'; END IF;
 current_from:=current_date;current_to:=current_date+365;
 FOR entry IN SELECT * FROM (VALUES
 ('DEMO-RH-MARRAKECH','Riad Jardin de l’Atlas','Marrakech','Maroc',4,85::numeric),
 ('DEMO-RH-PARIS','Maison Lumière','Paris','France',4,144::numeric),
 ('DEMO-RH-ISTANBUL','Bosphore Collection','Istanbul','Turquie',5,130::numeric)
 ) t(code,name,city,country,stars,nightly)
 LOOP
  SELECT d.hotel_id INTO v_hotel FROM public.demo_ratehawk_hotels_v8 d WHERE d.provider_code=entry.code;
  IF v_hotel IS NULL THEN
   INSERT INTO public.hotels(name,city,country,stars,description,status)
   VALUES(entry.name,entry.city,entry.country,entry.stars,'Établissement fictif du connecteur de démonstration RateHawk.',(SELECT CASE WHEN cfg.enabled THEN 'published' ELSE 'draft' END FROM public.netbeds_demo_settings_v8 cfg WHERE cfg.id=true)) RETURNING id INTO v_hotel;
   INSERT INTO public.demo_ratehawk_hotels_v8(hotel_id,provider_code) VALUES(v_hotel,entry.code);
   added:=added+1;
  END IF;
  INSERT INTO public.room_types(hotel_id,name,capacity,display_name,is_public) VALUES(v_hotel,'DBL',2,'Chambre double',true)
   ON CONFLICT(hotel_id,name) DO UPDATE SET is_public=true;
  DELETE FROM public.rates WHERE rates.hotel_id=v_hotel;
  INSERT INTO public.rates(hotel_id,room_name,board,date_start,date_end,net_price)
   VALUES(v_hotel,'DBL','RO',current_from,current_to,entry.nightly),
         (v_hotel,'DBL','BB',current_from,current_to,entry.nightly+18);
 END LOOP;
 RETURN added;
END $$;
REVOKE ALL ON FUNCTION public.admin_seed_ratehawk_demo_v8() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_seed_ratehawk_demo_v8() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_demo_mode_v8(p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Administrateur requis'; END IF;
 UPDATE public.netbeds_demo_settings_v8 SET enabled=p_enabled WHERE id=true;
 UPDATE public.hotels h SET status=CASE WHEN p_enabled THEN 'published' ELSE 'draft' END
 WHERE EXISTS(SELECT 1 FROM public.demo_ratehawk_hotels_v8 d WHERE d.hotel_id=h.id);
END $$;
REVOKE ALL ON FUNCTION public.admin_set_demo_mode_v8(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_demo_mode_v8(boolean) TO authenticated;

CREATE TABLE IF NOT EXISTS public.booking_guest_details_v8 (
 booking_id uuid PRIMARY KEY REFERENCES public.booking_requests(id) ON DELETE CASCADE,
 contact_email text NOT NULL,
 contact_phone text NOT NULL,
 nationality text NOT NULL,
 special_requests text NOT NULL DEFAULT '',
 guests jsonb NOT NULL DEFAULT '[]'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.booking_guest_details_v8 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS booking_guest_details_v8_read ON public.booking_guest_details_v8;
CREATE POLICY booking_guest_details_v8_read ON public.booking_guest_details_v8 FOR SELECT TO authenticated
 USING(public.is_admin() OR EXISTS (SELECT 1 FROM public.booking_requests b WHERE b.id=booking_id
 AND (b.agency_id=public.my_agency() OR EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=b.hotel_id AND h.dmc_id=public.my_dmc()))));
GRANT SELECT ON public.booking_guest_details_v8 TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.booking_guest_details_v8 FROM authenticated,anon;
CREATE OR REPLACE FUNCTION public.agency_booking_guests_v8(p_booking uuid,p_email text,p_phone text,p_nationality text,p_special text,p_guests jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b public.booking_requests;
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non autorisée'; END IF;
 SELECT * INTO b FROM public.booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR b.agency_id<>public.my_agency() OR b.status<>'pending' THEN RAISE EXCEPTION 'Dossier non modifiable'; END IF;
 IF length(trim(coalesce(p_email,'')))<5 OR position('@' in p_email)=0 OR length(trim(coalesce(p_phone,'')))<5 OR length(trim(coalesce(p_nationality,'')))<2 THEN RAISE EXCEPTION 'Coordonnées du voyageur invalides'; END IF;
 IF jsonb_typeof(p_guests)<>'array' OR jsonb_array_length(p_guests)<1 OR jsonb_array_length(p_guests)>40 THEN RAISE EXCEPTION 'Liste des voyageurs invalide'; END IF;
 IF length(coalesce(p_special,''))>1500 THEN RAISE EXCEPTION 'Demande spéciale trop longue'; END IF;
 INSERT INTO public.booking_guest_details_v8(booking_id,contact_email,contact_phone,nationality,special_requests,guests)
 VALUES(p_booking,trim(p_email),trim(p_phone),trim(p_nationality),coalesce(p_special,''),p_guests)
 ON CONFLICT(booking_id) DO UPDATE SET contact_email=excluded.contact_email,contact_phone=excluded.contact_phone,nationality=excluded.nationality,special_requests=excluded.special_requests,guests=excluded.guests;
END $$;
REVOKE ALL ON FUNCTION public.agency_booking_guests_v8(uuid,text,text,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.agency_booking_guests_v8(uuid,text,text,text,text,jsonb) TO authenticated;

-- Recalculate the effective agency/hotel markup at submission, not only at display.
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
 SELECT coalesce(m.markup_percent,ag.markup_percent) INTO markup FROM public.agencies ag
 LEFT JOIN public.agency_hotel_markups m ON m.agency_id=ag.id AND m.hotel_id=p_hotel
 WHERE ag.id=a AND ag.approved=true FOR UPDATE OF ag;
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

-- Submit guest identity and credit hold atomically. No orphan hold if passenger details fail validation.
CREATE OR REPLACE FUNCTION public.submit_booking_with_guests_v8(
 p_hotel uuid,p_room text,p_board text,p_checkin date,p_checkout date,p_guest text,
 p_room_count integer,p_adults integer,p_children integer,
 p_email text,p_phone text,p_nationality text,p_special text,p_guests jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE booking uuid;
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non autorisée'; END IF;
 IF length(trim(coalesce(p_email,'')))<5 OR position('@' in p_email)=0 OR length(trim(coalesce(p_phone,'')))<5 OR length(trim(coalesce(p_nationality,'')))<2 THEN RAISE EXCEPTION 'Coordonnées du voyageur invalides'; END IF;
 IF jsonb_typeof(p_guests)<>'array' OR jsonb_array_length(p_guests)<1 OR jsonb_array_length(p_guests)>40 THEN RAISE EXCEPTION 'Liste des voyageurs invalide'; END IF;
 IF length(coalesce(p_special,''))>1500 THEN RAISE EXCEPTION 'Demande spéciale trop longue'; END IF;
 booking:=public.submit_booking_v7(p_hotel,p_room,p_board,p_checkin,p_checkout,p_guest,p_room_count,p_adults,p_children);
 INSERT INTO public.booking_guest_details_v8(booking_id,contact_email,contact_phone,nationality,special_requests,guests)
 VALUES(booking,trim(p_email),trim(p_phone),trim(p_nationality),coalesce(p_special,''),p_guests);
 RETURN booking;
END $$;
REVOKE ALL ON FUNCTION public.submit_booking_with_guests_v8(uuid,text,text,date,date,text,integer,integer,integer,text,text,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_booking_with_guests_v8(uuid,text,text,date,date,text,integer,integer,integer,text,text,text,text,jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_booking_v7(uuid,text,text,date,date,text,integer,integer,integer) FROM PUBLIC,anon,authenticated;

-- Manual review of an unresolved mock booking attributes debt to its demo API supplier.
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
  payee_type:=CASE WHEN EXISTS(SELECT 1 FROM public.demo_ratehawk_hotels_v8 x WHERE x.hotel_id=b.hotel_id) THEN 'api' WHEN dn IS NULL THEN 'hotel' ELSE 'dmc' END;
  INSERT INTO public.supplier_payables(beneficiary_name,beneficiary_type,booking_id,amount_eur,reference,status)
  VALUES(CASE WHEN payee_type='api' THEN 'RateHawk — simulation' ELSE coalesce(dn,hn,'Hôtel contracté') END,payee_type,b.id,b.net_total_eur,'RES-'||left(b.id::text,8),'draft');
 ELSE
  UPDATE public.booking_holds_v7 SET state='released',finalized_at=now() WHERE booking_id=p_booking;
 END IF;
 UPDATE public.booking_requests SET status=p_status WHERE id=p_booking;
 UPDATE public.demo_ratehawk_bookings_v8 SET outcome=CASE WHEN p_status='confirmed' THEN 'confirmed' ELSE 'rejected' END WHERE booking_id=p_booking AND outcome='pending';
 INSERT INTO public.finance_audit(event,entity_id,details) VALUES('booking_'||p_status||'_v7',p_booking,
 jsonb_build_object('amount_eur',b.total_eur,'supplier_eur',b.net_total_eur,'agency_id',b.agency_id));
END $$;

-- A simulated supplier response. Pending is retained; repeated calls cannot double-charge.
CREATE OR REPLACE FUNCTION public.demo_ratehawk_resolve_v8(p_booking uuid,p_outcome text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b public.booking_requests; hold public.booking_holds_v7; enabled boolean;
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non approuvée'; END IF;
 SELECT s.enabled INTO enabled FROM public.netbeds_demo_settings_v8 s WHERE s.id=true;
 IF coalesce(enabled,false)=false THEN RAISE EXCEPTION 'Connecteur démonstration désactivé'; END IF;
 IF p_outcome NOT IN ('confirmed','rejected','pending') THEN RAISE EXCEPTION 'Scénario invalide'; END IF;
 SELECT * INTO b FROM public.booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR b.agency_id<>public.my_agency() THEN RAISE EXCEPTION 'Dossier non autorisé'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.demo_ratehawk_hotels_v8 d WHERE d.hotel_id=b.hotel_id) THEN RAISE EXCEPTION 'Ce dossier ne provient pas du fournisseur simulé'; END IF;
 IF EXISTS(SELECT 1 FROM public.demo_ratehawk_bookings_v8 WHERE booking_id=b.id) THEN RAISE EXCEPTION 'Scénario fournisseur déjà enregistré : opération non répétable'; END IF;
 IF b.status<>'pending' THEN RAISE EXCEPTION 'Dossier déjà traité'; END IF;
 SELECT * INTO hold FROM public.booking_holds_v7 WHERE booking_id=b.id FOR UPDATE;
 IF NOT FOUND OR hold.state<>'active' THEN RAISE EXCEPTION 'Blocage financier introuvable'; END IF;
 PERFORM 1 FROM public.agencies WHERE id=b.agency_id FOR UPDATE;
 INSERT INTO public.demo_ratehawk_bookings_v8(booking_id,outcome,supplier_reference)
 VALUES(b.id,p_outcome,CASE WHEN p_outcome='confirmed' THEN 'MOCK-RH-'||left(b.id::text,12) ELSE NULL END);
 IF p_outcome='confirmed' THEN
  INSERT INTO public.wallet_entries(agency_id,amount_eur,entry_type,note,booking_id)
  VALUES(b.agency_id,-b.total_eur,'booking_debit','Confirmation du fournisseur simulé',b.id);
  UPDATE public.booking_holds_v7 SET state='captured',finalized_at=now() WHERE booking_id=b.id;
  INSERT INTO public.supplier_payables(beneficiary_name,beneficiary_type,booking_id,amount_eur,reference,status)
  VALUES('RateHawk — simulation','api',b.id,b.net_total_eur,'RES-'||left(b.id::text,8),'draft');
  UPDATE public.booking_requests SET status='confirmed' WHERE id=b.id;
 ELSIF p_outcome='rejected' THEN
  UPDATE public.booking_holds_v7 SET state='released',finalized_at=now() WHERE booking_id=b.id;
  UPDATE public.booking_requests SET status='rejected' WHERE id=b.id;
 END IF;
 INSERT INTO public.finance_audit(event,entity_id,details) VALUES('mock_ratehawk_'||p_outcome,b.id,jsonb_build_object('amount_eur',b.total_eur,'net_eur',b.net_total_eur));
 RETURN p_outcome;
END $$;
REVOKE ALL ON FUNCTION public.demo_ratehawk_resolve_v8(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.demo_ratehawk_resolve_v8(uuid,text) TO authenticated;
COMMIT;
