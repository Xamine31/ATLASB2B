-- NETBEDS V9 : profil utilisateur et gestion sécurisée des hôtels.
-- Appliquer uniquement après les migrations V5 à V8 sur une copie de la base de test.
BEGIN;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bio text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS company text NOT NULL DEFAULT '';

-- L'utilisateur peut éditer uniquement ses données de présentation, jamais son rôle.
DROP POLICY IF EXISTS profiles_v9_update_self ON public.profiles;
CREATE POLICY profiles_v9_update_self ON public.profiles
 FOR UPDATE TO authenticated USING (id=(SELECT auth.uid()))
 WITH CHECK (id=(SELECT auth.uid()));
REVOKE UPDATE ON TABLE public.profiles FROM authenticated;
GRANT UPDATE (display_name,avatar_url,bio,phone,company) ON TABLE public.profiles TO authenticated;

INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES ('account-avatars','account-avatars',true,2097152,ARRAY['image/png','image/jpeg','image/webp'])
ON CONFLICT (id) DO UPDATE SET file_size_limit=2097152,allowed_mime_types=ARRAY['image/png','image/jpeg','image/webp'];
DROP POLICY IF EXISTS account_avatars_v9_read ON storage.objects;
CREATE POLICY account_avatars_v9_read ON storage.objects FOR SELECT TO authenticated
 USING (bucket_id='account-avatars');
DROP POLICY IF EXISTS account_avatars_v9_insert ON storage.objects;
CREATE POLICY account_avatars_v9_insert ON storage.objects FOR INSERT TO authenticated
 WITH CHECK (bucket_id='account-avatars' AND (storage.foldername(name))[1]=(SELECT auth.uid())::text);
DROP POLICY IF EXISTS account_avatars_v9_delete ON storage.objects;
CREATE POLICY account_avatars_v9_delete ON storage.objects FOR DELETE TO authenticated
 USING (bucket_id='account-avatars' AND (storage.foldername(name))[1]=(SELECT auth.uid())::text);

-- Suppression uniquement d'un hôtel en brouillon sans réservation référencée.
-- Requiert un appel explicitement confirmé par l'utilisateur depuis la page suppression.
CREATE OR REPLACE FUNCTION public.delete_draft_hotel_v9(p_hotel uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE h public.hotels%ROWTYPE;
BEGIN
 SELECT * INTO h FROM public.hotels WHERE id=p_hotel FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Hôtel introuvable'; END IF;
 IF NOT (public.is_admin() OR (public.my_role()='dmc' AND h.dmc_id=public.my_dmc())) THEN
   RAISE EXCEPTION 'Accès refusé';
 END IF;
 IF h.status<>'draft' THEN RAISE EXCEPTION 'La suppression est réservée aux hôtels en brouillon'; END IF;
 IF EXISTS(SELECT 1 FROM public.booking_requests WHERE hotel_id=p_hotel) THEN
   RAISE EXCEPTION 'Hôtel lié à des réservations : suppression interdite';
 END IF;
 IF EXISTS(SELECT 1 FROM public.hotel_contracts_v8 WHERE hotel_id=p_hotel AND status<>'draft') THEN
   RAISE EXCEPTION 'Hôtel lié à un contrat actif ou historisé : suppression interdite';
 END IF;
 DELETE FROM public.hotel_contracts_v8 WHERE hotel_id=p_hotel;
 DELETE FROM public.hotels WHERE id=p_hotel;
END $$;
REVOKE ALL ON FUNCTION public.delete_draft_hotel_v9(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_draft_hotel_v9(uuid) TO authenticated;
COMMIT;
