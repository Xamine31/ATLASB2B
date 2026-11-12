-- AtlasB2B - INSTALLATION SUR UN PROJET SUPABASE DE TEST VIERGE
-- Aucune transaction bancaire réelle. Toute réservation est une DEMANDE manuelle.
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table public.agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null, approved boolean not null default false,
  markup_percent numeric(6,2) not null default 5 check (markup_percent between 0 and 100),
  created_at timestamptz not null default now()
);
create table public.dmcs (
  id uuid primary key default gen_random_uuid(),name text not null,
  approved boolean not null default false,created_at timestamptz not null default now()
);
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,display_name text not null default '',
  role text not null default 'agency' check (role in ('admin','dmc','agency')),
  agency_id uuid references public.agencies(id), dmc_id uuid references public.dmcs(id),
  created_at timestamptz not null default now(),
  constraint one_tenant check ((role='admin' and agency_id is null and dmc_id is null) or (role='agency' and agency_id is not null and dmc_id is null) or (role='dmc' and agency_id is null and dmc_id is not null))
);

create or replace function public.on_signup() returns trigger language plpgsql security definer set search_path = public as $$
declare ag_id uuid;
begin
  insert into public.agencies(name) values(coalesce(nullif(split_part(new.email,'@',1),''),'Nouvelle agence')) returning id into ag_id;
  insert into public.profiles(id,email,display_name,role,agency_id) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'name',''),'agency',ag_id);
  return new;
end $$;
create trigger after_auth_signup after insert on auth.users for each row execute function public.on_signup();

create or replace function public.my_role() returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id=(select auth.uid())
$$;
create or replace function public.my_agency() returns uuid language sql stable security definer set search_path = public as $$
  select agency_id from public.profiles where id=(select auth.uid())
$$;
create or replace function public.my_dmc() returns uuid language sql stable security definer set search_path = public as $$
  select dmc_id from public.profiles where id=(select auth.uid())
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role()='admin',false)
$$;
create or replace function public.is_approved_agency() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.agencies where id=public.my_agency() and approved)
$$;

create table public.hotels (
  id uuid primary key default gen_random_uuid(), dmc_id uuid references public.dmcs(id),
  name text not null,city text not null,country text not null default 'Maroc',
  description text not null default '',stars int not null default 3 check (stars between 1 and 5),
  cover_url text,status text not null default 'draft' check (status in ('draft','published')),
  created_at timestamptz not null default now()
);
create table public.room_types (
  id uuid primary key default gen_random_uuid(),hotel_id uuid not null references public.hotels(id) on delete cascade,
  name text not null,capacity int not null default 2 check (capacity between 1 and 20),
  description text not null default '',photo_url text,
  unique(hotel_id,name)
);
create table public.rates (
  id uuid primary key default gen_random_uuid(),hotel_id uuid not null references public.hotels(id) on delete cascade,
  room_name text not null,board text not null check(board in ('RO','BB','HB','FB','ALL IN')),
  date_start date not null,date_end date not null,net_price numeric(12,2) not null check(net_price>=0),
  created_at timestamptz not null default now(),
  check(date_end>=date_start),unique(hotel_id,room_name,board,date_start,date_end),
  exclude using gist (hotel_id with =, room_name with =, board with =, daterange(date_start,date_end,'[]') with &&)
);
create table public.api_suppliers (
  id uuid primary key default gen_random_uuid(),name text not null unique,adapter text not null,
  enabled boolean not null default false,notes text not null default '',created_at timestamptz default now()
);
create table public.booking_requests (
  id uuid primary key default gen_random_uuid(),agency_id uuid not null references public.agencies(id),
  hotel_id uuid not null references public.hotels(id),room_name text not null,board text not null,
  checkin date not null,checkout date not null,guest_name text not null,
  total_eur numeric(12,2) not null,net_total_eur numeric(12,2) not null,
  status text not null default 'pending' check(status in ('pending','confirmed','rejected')),
  created_at timestamptz not null default now(),
  check(checkout>checkin)
);

-- RLS activé par défaut sur toutes les tables
alter table public.agencies enable row level security;
alter table public.dmcs enable row level security;
alter table public.profiles enable row level security;
alter table public.hotels enable row level security;
alter table public.room_types enable row level security;
alter table public.rates enable row level security;
alter table public.api_suppliers enable row level security;
alter table public.booking_requests enable row level security;
create policy agencies_read on public.agencies for select to authenticated using (public.is_admin() or id=public.my_agency());
create policy agencies_admin_update on public.agencies for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy dmcs_read on public.dmcs for select to authenticated using(public.is_admin() or id=public.my_dmc());
create policy profiles_read on public.profiles for select to authenticated using(public.is_admin() or id=(select auth.uid()));
create policy hotels_read on public.hotels for select to authenticated using(public.is_admin() or dmc_id=public.my_dmc() or (status='published' and public.is_approved_agency()));
create policy hotels_insert on public.hotels for insert to authenticated with check(public.is_admin() or (public.my_role()='dmc' and dmc_id=public.my_dmc() and status='draft'));
create policy hotels_update on public.hotels for update to authenticated using(public.is_admin() or (dmc_id=public.my_dmc() and status='draft')) with check(public.is_admin() or (dmc_id=public.my_dmc() and status='draft'));
create policy room_read on public.room_types for select to authenticated using(exists(select 1 from public.hotels h where h.id=hotel_id and (public.is_admin() or h.dmc_id=public.my_dmc() or (h.status='published' and public.is_approved_agency()))));
create policy room_write on public.room_types for insert to authenticated with check(exists(select 1 from public.hotels h where h.id=hotel_id and (public.is_admin() or (h.status='draft' and h.dmc_id=public.my_dmc()))));
create policy room_edit on public.room_types for update to authenticated using(exists(select 1 from public.hotels h where h.id=hotel_id and (public.is_admin() or (h.status='draft' and h.dmc_id=public.my_dmc())))) with check(exists(select 1 from public.hotels h where h.id=hotel_id and (public.is_admin() or (h.status='draft' and h.dmc_id=public.my_dmc()))));
create policy rates_read on public.rates for select to authenticated using(public.is_admin() or exists(select 1 from public.hotels h where h.id=hotel_id and h.dmc_id=public.my_dmc()));
create policy rates_write on public.rates for insert to authenticated with check(public.is_admin() or exists(select 1 from public.hotels h where h.id=hotel_id and h.dmc_id=public.my_dmc() and h.status='draft'));
create policy rates_update on public.rates for update to authenticated using(public.is_admin() or exists(select 1 from public.hotels h where h.id=hotel_id and h.dmc_id=public.my_dmc() and h.status='draft')) with check(public.is_admin() or exists(select 1 from public.hotels h where h.id=hotel_id and h.dmc_id=public.my_dmc() and h.status='draft'));
create policy rates_delete on public.rates for delete to authenticated using(public.is_admin() or exists(select 1 from public.hotels h where h.id=hotel_id and h.dmc_id=public.my_dmc() and h.status='draft'));
create policy suppliers_admin_read on public.api_suppliers for select to authenticated using(public.is_admin());
create policy suppliers_admin_insert on public.api_suppliers for insert to authenticated with check(public.is_admin());
create policy suppliers_admin_update on public.api_suppliers for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy booking_read on public.booking_requests for select to authenticated using(public.is_admin() or agency_id=public.my_agency() or exists(select 1 from public.hotels h where h.id=hotel_id and h.dmc_id=public.my_dmc()));
-- Aucun INSERT / UPDATE direct sur booking_requests: via RPC ci-dessous.

-- Seul l'admin peut approuver agences, promouvoir DMC, publier les hôtels, ou changer la marge.
create or replace function public.admin_set_user(p_user uuid,p_role text,p_approve boolean default true)
returns void language plpgsql security definer set search_path=public as $$
declare pr public.profiles; new_id uuid;
begin
 if not public.is_admin() then raise exception 'Administrateur requis'; end if;
 if p_user=(select auth.uid()) then raise exception 'Modification de soi interdite'; end if;
 select * into pr from public.profiles where id=p_user for update;
 if not found then raise exception 'Utilisateur introuvable'; end if;
 if p_role='agency' and pr.role='agency' then
   update public.agencies set approved=p_approve where id=pr.agency_id;
 elsif p_role='dmc' and pr.role in ('agency','dmc') then
   if pr.role='agency' then
     insert into public.dmcs(name,approved) values(pr.display_name,p_approve) returning id into new_id;
     update public.profiles set role='dmc',agency_id=null,dmc_id=new_id where id=p_user;
   else update public.dmcs set approved=p_approve where id=pr.dmc_id; end if;
 else raise exception 'Action non autorisée'; end if;
end $$;
revoke all on function public.admin_set_user(uuid,text,boolean) from public;
grant execute on function public.admin_set_user(uuid,text,boolean) to authenticated;

-- Renvoie uniquement des tarifs de vente, jamais les tarifs nets aux agences.
create or replace function public.hotel_offers(p_checkin date,p_checkout date,p_city text default '')
returns table(hotel_id uuid,hotel_name text,city text,stars int,cover_url text,room_name text,board text,total_price numeric)
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_approved_agency() then raise exception 'Agence non activée'; end if;
 if p_checkout<=p_checkin or p_checkout>p_checkin+interval '30 days' or p_checkin<current_date then raise exception 'Dates invalides (30 nuits max)';end if;
 return query
 with nights as (select gs::date as night from generate_series(p_checkin::timestamp,(p_checkout-1)::timestamp,'1 day') gs),
 options as (select h.id hid,h.name hn,h.city hc,h.stars hs,h.cover_url hu,r.room_name rn,r.board rb,
 (select sum(r2.net_price) from nights n join public.rates r2 on r2.hotel_id=h.id and r2.room_name=r.room_name and r2.board=r.board and n.night between r2.date_start and r2.date_end) net,
 (select count(*) from nights n where exists(select 1 from public.rates r2 where r2.hotel_id=h.id and r2.room_name=r.room_name and r2.board=r.board and n.night between r2.date_start and r2.date_end)) available_nights
 from public.hotels h join public.rates r on r.hotel_id=h.id
 where h.status='published' and (coalesce(p_city,'')='' or h.city ilike '%'||p_city||'%')
 group by h.id,h.name,h.city,h.stars,h.cover_url,r.room_name,r.board)
 select o.hid,o.hn,o.hc,o.hs,o.hu,o.rn,o.rb,round(o.net*(1+a.markup_percent/100),2)
 from options o join public.agencies a on a.id=public.my_agency()
 where o.available_nights=(p_checkout-p_checkin) and o.net is not null
 order by o.hn,o.rn;
end $$;
revoke all on function public.hotel_offers(date,date,text) from public;
grant execute on function public.hotel_offers(date,date,text) to authenticated;

create or replace function public.submit_booking(p_hotel uuid,p_room text,p_board text,p_checkin date,p_checkout date,p_guest text)
returns uuid language plpgsql security definer set search_path=public as $$
declare net_total numeric;cnt int;days int;hotel_ok boolean;markup numeric;out_id uuid;
begin
 if not public.is_approved_agency() then raise exception 'Agence non activée';end if;
 if p_checkout<=p_checkin or p_checkout>p_checkin+interval '30 days' or p_checkin<current_date then raise exception 'Dates invalides';end if;
 if length(trim(p_guest))<3 then raise exception 'Nom de voyageur requis';end if;
 select status='published' into hotel_ok from public.hotels where id=p_hotel;
 if not coalesce(hotel_ok,false) then raise exception 'Hôtel indisponible';end if;
 select count(*),sum(net_price) into cnt,net_total from (
 select n.night,(select r.net_price from public.rates r where r.hotel_id=p_hotel and r.room_name=p_room and r.board=p_board and n.night between r.date_start and r.date_end limit 1) net_price
 from (select gs::date night from generate_series(p_checkin::timestamp,(p_checkout-1)::timestamp,'1 day') gs)n
 ) q where net_price is not null;
 days:=p_checkout-p_checkin;
 if cnt<>days then raise exception 'Tarif manquant pour ces dates';end if;
 select markup_percent into markup from public.agencies where id=public.my_agency();
 insert into public.booking_requests(agency_id,hotel_id,room_name,board,checkin,checkout,guest_name,total_eur,net_total_eur)
 values(public.my_agency(),p_hotel,p_room,p_board,p_checkin,p_checkout,trim(p_guest),round(net_total*(1+markup/100),2),net_total) returning id into out_id;
 return out_id;
end $$;
revoke all on function public.submit_booking(uuid,text,text,date,date,text) from public;
grant execute on function public.submit_booking(uuid,text,text,date,date,text) to authenticated;

create or replace function public.admin_booking_status(p_booking uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Administrateur requis';end if;
 if p_status not in ('confirmed','rejected') then raise exception 'Statut invalide';end if;
 update public.booking_requests set status=p_status where id=p_booking and status='pending';
 if not found then raise exception 'Dossier non modifiable';end if;
end $$;
revoke all on function public.admin_booking_status(uuid,text) from public;
grant execute on function public.admin_booking_status(uuid,text) to authenticated;

-- Bucket photos public, écriture isolée par identifiant de l'utilisateur.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('hotel-photos','hotel-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy photo_public_read on storage.objects for select to public using(bucket_id='hotel-photos');
create policy photo_upload_owner on storage.objects for insert to authenticated
with check(bucket_id='hotel-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- APRÈS inscription d'un compte dans l'application, exécuter EN PRIVÉ dans SQL Editor :
-- update public.profiles set role='admin',agency_id=null,dmc_id=null where email='votre-email@exemple.fr';
-- Ne jamais utiliser cette requête avec une saisie provenant du navigateur.
