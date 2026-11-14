-- Migration de la première version AtlasB2B vers la reconstruction V2.
-- À exécuter UNIQUEMENT si les tables de la version précédente existent déjà.
-- Effectuer une sauvegarde avant toute migration.
revoke all on public.booking_requests from anon, authenticated;
grant select (id,agency_id,hotel_id,room_name,board,checkin,checkout,guest_name,total_eur,status,created_at)
  on public.booking_requests to authenticated;

-- Restriction des nouveaux uploads aux administrateurs et aux DMC.
drop policy if exists photo_upload_owner on storage.objects;
create policy photo_upload_owner on storage.objects for insert to authenticated
with check(bucket_id='hotel-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and (public.is_admin() or public.my_role()='dmc'));

-- Import tarifaire atomique : si une ligne échoue, AUCUN tarif n'est modifié.
-- Les dates couvertes par le nouveau fichier remplacent les tarifs existants sur ce périmètre.
create or replace function public.replace_hotel_rates(p_hotel uuid,p_rows jsonb)
returns integer language plpgsql security definer set search_path=public as $$
declare h public.hotels; r jsonb; dmin date; dmax date; n integer;
begin
  select * into h from public.hotels where id=p_hotel for update;
  if not found then raise exception 'Hôtel introuvable'; end if;
  if not (public.is_admin() or (public.my_role()='dmc' and h.dmc_id=public.my_dmc() and h.status='draft'))
    then raise exception 'Modification tarifaire non autorisée'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) < 1 or jsonb_array_length(p_rows)>3000
    then raise exception 'Fichier tarifaire invalide ou trop volumineux'; end if;
  select min((e->>'date_start')::date),max((e->>'date_end')::date) into dmin,dmax
    from jsonb_array_elements(p_rows) e;
  if dmin is null or dmax is null or dmax < dmin or dmax>dmin+interval '2 years'
    then raise exception 'Période tarifaire invalide'; end if;
  delete from public.rates where hotel_id=p_hotel and date_start<=dmax and date_end>=dmin;
  for r in select value from jsonb_array_elements(p_rows) loop
    if coalesce(length(trim(r->>'room_name')),0)<1 or (r->>'board') not in ('RO','BB','HB','FB','ALL IN')
      or (r->>'net_price')::numeric <0 or (r->>'date_start')::date>(r->>'date_end')::date
      then raise exception 'Ligne de tarif incorrecte'; end if;
    insert into public.room_types(hotel_id,name) values(p_hotel,trim(r->>'room_name')) on conflict(hotel_id,name) do nothing;
    insert into public.rates(hotel_id,room_name,board,date_start,date_end,net_price)
    values(p_hotel,trim(r->>'room_name'),r->>'board',(r->>'date_start')::date,(r->>'date_end')::date,(r->>'net_price')::numeric);
  end loop;
  get diagnostics n = row_count;
  return jsonb_array_length(p_rows);
end $$;
revoke all on function public.replace_hotel_rates(uuid,jsonb) from public;
grant execute on function public.replace_hotel_rates(uuid,jsonb) to authenticated;

