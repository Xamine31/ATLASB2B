-- AtlasB2B V6 - appliquer UNE fois après V5 sur une base Supabase de TEST.
-- Sauvegarder la base avant la migration. Aucune table financière n'est supprimée.
BEGIN;
ALTER TABLE public.room_types ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT true;
ALTER TABLE public.room_types ADD COLUMN IF NOT EXISTS display_name text;
-- Les agences ne doivent pas pouvoir lire les chambres masquées via PostgREST.
DROP POLICY IF EXISTS room_read ON public.room_types;
CREATE POLICY room_read ON public.room_types FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND
   (public.is_admin() OR h.dmc_id=public.my_dmc() OR (h.status='published' AND public.is_approved_agency() AND is_public))));


CREATE TABLE IF NOT EXISTS public.hotel_promotions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 hotel_id uuid NOT NULL REFERENCES public.hotels(id) ON DELETE CASCADE,
 code text NOT NULL,
 label text NOT NULL,
 kind text NOT NULL CHECK(kind IN ('child','special')),
 discount_percent numeric(5,2) NOT NULL DEFAULT 0 CHECK(discount_percent >= 0 AND discount_percent <= 100),
 description text NOT NULL DEFAULT '',
 is_public boolean NOT NULL DEFAULT false,
 imported boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(hotel_id,code)
);
CREATE TABLE IF NOT EXISTS public.hotel_promotion_periods (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 promotion_id uuid NOT NULL REFERENCES public.hotel_promotions(id) ON DELETE CASCADE,
 date_start date NOT NULL,date_end date NOT NULL,
 discount_percent numeric(5,2) NOT NULL CHECK(discount_percent BETWEEN 0 AND 100),
 CHECK(date_end>=date_start),UNIQUE(promotion_id,date_start,date_end)
);
ALTER TABLE public.hotel_promotion_periods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS promo_periods_read ON public.hotel_promotion_periods;
CREATE POLICY promo_periods_read ON public.hotel_promotion_periods FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.hotel_promotions p JOIN public.hotels h ON h.id=p.hotel_id WHERE p.id=promotion_id
 AND (public.is_admin() OR h.dmc_id=public.my_dmc() OR (h.status='published' AND public.is_approved_agency() AND p.is_public))));
DROP POLICY IF EXISTS promo_periods_write ON public.hotel_promotion_periods;
CREATE POLICY promo_periods_write ON public.hotel_promotion_periods FOR ALL TO authenticated
 USING(EXISTS(SELECT 1 FROM public.hotel_promotions p JOIN public.hotels h ON h.id=p.hotel_id WHERE p.id=promotion_id AND
 (public.is_admin() OR (h.status='draft' AND h.dmc_id=public.my_dmc()))))
 WITH CHECK(EXISTS(SELECT 1 FROM public.hotel_promotions p JOIN public.hotels h ON h.id=p.hotel_id WHERE p.id=promotion_id AND
 (public.is_admin() OR (h.status='draft' AND h.dmc_id=public.my_dmc()))));
GRANT SELECT,INSERT,UPDATE,DELETE ON public.hotel_promotion_periods TO authenticated;
ALTER TABLE public.hotel_promotions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hotel_promotions_read ON public.hotel_promotions;
CREATE POLICY hotel_promotions_read ON public.hotel_promotions FOR SELECT TO authenticated
 USING(public.is_admin() OR EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND (h.dmc_id=public.my_dmc() OR (h.status='published' AND public.is_approved_agency() AND is_public))));
DROP POLICY IF EXISTS hotel_promotions_write ON public.hotel_promotions;
CREATE POLICY hotel_promotions_write ON public.hotel_promotions FOR ALL TO authenticated
 USING(public.is_admin() OR EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND h.dmc_id=public.my_dmc() AND h.status='draft'))
 WITH CHECK(public.is_admin() OR EXISTS(SELECT 1 FROM public.hotels h WHERE h.id=hotel_id AND h.dmc_id=public.my_dmc() AND h.status='draft'));
GRANT SELECT,INSERT,UPDATE,DELETE ON public.hotel_promotions TO authenticated;

-- Import transactionnel: le moindre problème annule TOUTE l'opération.
CREATE OR REPLACE FUNCTION public.import_hotel_excel_v6(p_hotel uuid,p_rates jsonb,p_promotions jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE h public.hotels; r jsonb; p jsonb; season jsonb; promo_id uuid; dmin date; dmax date; n integer;
BEGIN
 SELECT * INTO h FROM public.hotels WHERE id=p_hotel FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Hôtel introuvable'; END IF;
 IF NOT (public.is_admin() OR (public.my_role()='dmc' AND h.dmc_id=public.my_dmc() AND h.status='draft')) THEN RAISE EXCEPTION 'Modification interdite : seul l admin ou la DMC sur un brouillon peut importer'; END IF;
 IF jsonb_typeof(p_rates) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rates) NOT BETWEEN 1 AND 3000 THEN RAISE EXCEPTION 'Grille de tarifs invalide'; END IF;
 IF jsonb_typeof(p_promotions) IS DISTINCT FROM 'array' OR jsonb_array_length(p_promotions)>30 THEN RAISE EXCEPTION 'Promotions invalides'; END IF;
 SELECT min((v->>'date_start')::date),max((v->>'date_end')::date) INTO dmin,dmax FROM jsonb_array_elements(p_rates) v;
 IF dmin IS NULL OR dmax<dmin OR dmax>dmin+interval '2 years' THEN RAISE EXCEPTION 'Saison tarifaire hors limite'; END IF;
 -- Valider toutes les données avant suppression des tarifs précédents.
 FOR r IN SELECT value FROM jsonb_array_elements(p_rates) LOOP
  IF length(trim(coalesce(r->>'room_name','')))=0 OR r->>'board' NOT IN ('RO','BB','HB','FB','ALL IN')
   OR (r->>'net_price')::numeric<0 OR (r->>'net_price')::numeric>100000
   OR (r->>'date_start')::date>(r->>'date_end')::date
   OR (r->>'date_start')::date<dmin OR (r->>'date_end')::date>dmax
  THEN RAISE EXCEPTION 'Ligne tarifaire invalide'; END IF;
 END LOOP;
 -- Les tarifs de la saison importée sont remplacés comme un ensemble.
 DELETE FROM public.rates WHERE hotel_id=p_hotel AND date_start<=dmax AND date_end>=dmin;
 FOR r IN SELECT value FROM jsonb_array_elements(p_rates) LOOP
  INSERT INTO public.room_types(hotel_id,name,capacity,display_name,is_public)
  VALUES(p_hotel,trim(r->>'room_name'),CASE WHEN upper(r->>'room_name') LIKE 'SGL%' THEN 1 WHEN upper(r->>'room_name') LIKE 'QDL%' THEN 4 WHEN upper(r->>'room_name') LIKE 'TR%L%' THEN 3 ELSE 2 END,trim(r->>'room_name'),true)
  ON CONFLICT(hotel_id,name) DO NOTHING;
  INSERT INTO public.rates(hotel_id,room_name,board,date_start,date_end,net_price)
  VALUES(p_hotel,trim(r->>'room_name'),r->>'board',(r->>'date_start')::date,(r->>'date_end')::date,(r->>'net_price')::numeric);
 END LOOP;
 FOR p IN SELECT value FROM jsonb_array_elements(p_promotions) LOOP
  IF coalesce(p->>'code','') NOT IN ('CHILD_0_2','CHILD_2_6','CHILD_6_11','THIRD_ADULT','EARLY_BOOKING','HONEYMOON','SENIOR') OR (p->>'discount_percent')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Promotion invalide'; END IF;
  INSERT INTO public.hotel_promotions(hotel_id,code,label,kind,discount_percent,imported)
   VALUES(p_hotel,p->>'code',p->>'label',p->>'kind',(p->>'discount_percent')::numeric,true)
  ON CONFLICT(hotel_id,code) DO UPDATE SET discount_percent=excluded.discount_percent,imported=true,updated_at=now()
  RETURNING id INTO promo_id;
  DELETE FROM public.hotel_promotion_periods WHERE promotion_id=promo_id;
  FOR season IN SELECT value FROM jsonb_array_elements(coalesce(p->'periods','[]'::jsonb)) LOOP
   IF (season->>'discount_percent')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Réduction saisonnière invalide'; END IF;
   INSERT INTO public.hotel_promotion_periods(promotion_id,date_start,date_end,discount_percent)
   VALUES(promo_id,(season->>'date_start')::date,(season->>'date_end')::date,(season->>'discount_percent')::numeric);
  END LOOP;
  -- Ne jamais rendre publique une promotion simplement parce qu'elle figure dans Excel.
 END LOOP;
 RETURN jsonb_array_length(p_rates);
END $$;
REVOKE ALL ON FUNCTION public.import_hotel_excel_v6(uuid,jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.import_hotel_excel_v6(uuid,jsonb,jsonb) TO authenticated;

-- Recherche: seulement chambres rendues publiques, tarifs couvrant TOUTES les nuits.
-- Pas d'application automatique des remises: paramètres descriptifs soumis à validation.
CREATE OR REPLACE FUNCTION public.hotel_offers(p_checkin date,p_checkout date,p_city text DEFAULT '')
RETURNS TABLE(hotel_id uuid,hotel_name text,city text,stars int,cover_url text,room_name text,board text,total_price numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Compte agence non approuvé'; END IF;
 IF p_checkout<=p_checkin OR p_checkout>p_checkin+interval '30 days' OR p_checkin<current_date THEN RAISE EXCEPTION 'Dates invalides : séjour futur, 30 nuits maximum'; END IF;
 RETURN QUERY
 WITH nights AS (SELECT d::date AS night FROM generate_series(p_checkin::timestamp,(p_checkout-1)::timestamp,interval '1 day') d),
 offers AS (
  SELECT h.id hid,h.name hn,h.city hc,h.stars hs,h.cover_url hu,rt.name rn,r.board rb,
   (SELECT COUNT(*) FROM nights n WHERE EXISTS(SELECT 1 FROM public.rates rr WHERE rr.hotel_id=h.id AND rr.room_name=rt.name AND rr.board=r.board AND n.night BETWEEN rr.date_start AND rr.date_end)) days_covered,
   (SELECT SUM(rr.net_price) FROM nights n JOIN public.rates rr ON rr.hotel_id=h.id AND rr.room_name=rt.name AND rr.board=r.board AND n.night BETWEEN rr.date_start AND rr.date_end) net
  FROM public.hotels h JOIN public.room_types rt ON rt.hotel_id=h.id AND rt.is_public=true
   JOIN (SELECT DISTINCT hotel_id,room_name,board FROM public.rates) r ON r.hotel_id=h.id AND r.room_name=rt.name
  WHERE h.status='published' AND (trim(coalesce(p_city,''))='' OR h.city ILIKE '%'||trim(p_city)||'%' OR h.name ILIKE '%'||trim(p_city)||'%' OR h.country ILIKE '%'||trim(p_city)||'%')
 )
 SELECT o.hid,o.hn,o.hc,o.hs,o.hu,o.rn,o.rb,round(o.net*(1+a.markup_percent/100),2)
 FROM offers o JOIN public.agencies a ON a.id=public.my_agency()
 WHERE o.days_covered=(p_checkout-p_checkin) AND o.net IS NOT NULL
 ORDER BY o.hn,o.rn,o.rb;
END $$;
REVOKE ALL ON FUNCTION public.hotel_offers(date,date,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hotel_offers(date,date,text) TO authenticated;
-- Une réservation ne peut pas contourner la visibilité d'une chambre.
CREATE OR REPLACE FUNCTION public.submit_booking(p_hotel uuid,p_room text,p_board text,p_checkin date,p_checkout date,p_guest text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE net_total numeric; cnt integer; nights integer; markup numeric; result_id uuid;
BEGIN
 IF NOT public.is_approved_agency() THEN RAISE EXCEPTION 'Agence non activée'; END IF;
 IF p_checkout<=p_checkin OR p_checkout>p_checkin+interval '30 days' OR p_checkin<current_date THEN RAISE EXCEPTION 'Dates invalides'; END IF;
 IF length(trim(p_guest))<3 THEN RAISE EXCEPTION 'Nom du voyageur requis'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.hotels h JOIN public.room_types rt ON rt.hotel_id=h.id
   WHERE h.id=p_hotel AND h.status='published' AND rt.name=p_room AND rt.is_public=true) THEN RAISE EXCEPTION 'Chambre indisponible'; END IF;
 SELECT count(*),sum(t.net_price) INTO cnt,net_total FROM (
  SELECT (SELECT r.net_price FROM public.rates r WHERE r.hotel_id=p_hotel AND r.room_name=p_room AND r.board=p_board
      AND gs::date BETWEEN r.date_start AND r.date_end LIMIT 1) net_price
  FROM generate_series(p_checkin::timestamp,(p_checkout-1)::timestamp,interval '1 day') gs
 ) t WHERE t.net_price IS NOT NULL;
 nights:=p_checkout-p_checkin;
 IF cnt<>nights THEN RAISE EXCEPTION 'Tarifs incomplets pour ces dates'; END IF;
 SELECT markup_percent INTO markup FROM public.agencies WHERE id=public.my_agency();
 INSERT INTO public.booking_requests(agency_id,hotel_id,room_name,board,checkin,checkout,guest_name,total_eur,net_total_eur)
 VALUES(public.my_agency(),p_hotel,p_room,p_board,p_checkin,p_checkout,trim(p_guest),round(net_total*(1+markup/100),2),net_total)
 RETURNING id INTO result_id;
 RETURN result_id;
END $$;
REVOKE ALL ON FUNCTION public.submit_booking(uuid,text,text,date,date,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_booking(uuid,text,text,date,date,text) TO authenticated;

COMMIT;
