-- AtlasB2B V5 — à exécuter UNE seule fois après sauvegarde, après le schéma REBUILD.
-- ENVIRONNEMENT DE TEST UNIQUEMENT : aucune opération bancaire réelle.
-- Tous les montants sont exprimés en EUR. Toute écriture financière exige le rôle admin.
begin;

create table if not exists public.wallet_topup_requests (
 id uuid primary key default gen_random_uuid(),
 agency_id uuid not null references public.agencies(id),
 amount_eur numeric(12,2) not null check(amount_eur>0 and amount_eur<=1000000),
 transfer_reference text not null check(length(trim(transfer_reference)) between 3 and 120),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 requested_by uuid not null default auth.uid() references auth.users(id),
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.wallet_entries (
 id uuid primary key default gen_random_uuid(),
 agency_id uuid not null references public.agencies(id),
 amount_eur numeric(12,2) not null check(amount_eur <> 0),
 entry_type text not null check(entry_type in ('topup','booking_debit','refund','manual_adjustment')),
 note text not null check(length(trim(note))>=4),
 topup_request_id uuid unique references public.wallet_topup_requests(id),
 booking_id uuid references public.booking_requests(id),
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now()
);
create unique index if not exists wallet_one_booking_debit on public.wallet_entries(booking_id)
 where entry_type='booking_debit';
create table if not exists public.supplier_payables (
 id uuid primary key default gen_random_uuid(),
 beneficiary_name text not null check(length(trim(beneficiary_name))>=3),
 beneficiary_type text not null check(beneficiary_type in ('dmc','hotel','api')),
 booking_id uuid references public.booking_requests(id),
 amount_eur numeric(12,2) not null check(amount_eur>0),
 reference text not null,
 due_date date,
 status text not null default 'draft' check(status in ('draft','approved','paid','cancelled')),
 approved_by uuid references auth.users(id), approved_at timestamptz,
 paid_by uuid references auth.users(id), paid_at timestamptz,
 bank_reference text,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 constraint paid_requires_reference check(status<>'paid' or (bank_reference is not null and length(trim(bank_reference))>=4))
);
create table if not exists public.finance_audit (
 id bigint generated always as identity primary key,
 event text not null, entity_id uuid, details jsonb not null default '{}'::jsonb,
 actor uuid default auth.uid(), created_at timestamptz not null default now()
);

alter table public.wallet_topup_requests enable row level security;
alter table public.wallet_entries enable row level security;
alter table public.supplier_payables enable row level security;
alter table public.finance_audit enable row level security;

create policy topups_select on public.wallet_topup_requests for select to authenticated
 using(public.is_admin() or (agency_id=public.my_agency() and public.is_approved_agency()));
create policy topups_request on public.wallet_topup_requests for insert to authenticated
 with check(public.is_approved_agency() and agency_id=public.my_agency() and requested_by=auth.uid() and status='pending' and reviewed_by is null and reviewed_at is null);
create policy entries_select on public.wallet_entries for select to authenticated
 using(public.is_admin() or (agency_id=public.my_agency() and public.is_approved_agency()));
create policy payables_select on public.supplier_payables for select to authenticated using(public.is_admin());
create policy audit_select on public.finance_audit for select to authenticated using(public.is_admin());

-- Autoriser explicitement la lecture (filtrée par RLS), et la création des demandes agences.
grant select,insert on public.wallet_topup_requests to authenticated;
grant select on public.wallet_entries to authenticated;
grant select on public.supplier_payables to authenticated;
grant select on public.finance_audit to authenticated;

-- Refuser toutes les écritures directes des navigateurs sur les tables comptables.
revoke insert,update,delete on public.wallet_entries from anon,authenticated;
revoke update,delete on public.wallet_topup_requests from anon,authenticated;
revoke insert,update,delete on public.supplier_payables from anon,authenticated;
revoke insert,update,delete on public.finance_audit from anon,authenticated;

create or replace function public.admin_review_topup(p_request uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public as $$
declare r public.wallet_topup_requests;
begin
 if not public.is_admin() then raise exception 'Admin requis'; end if;
 select * into r from public.wallet_topup_requests where id=p_request for update;
 if not found or r.status<>'pending' then raise exception 'Demande inexistante ou déjà traitée'; end if;
 update public.wallet_topup_requests set status=case when p_approve then 'approved' else 'rejected' end,
 reviewed_by=auth.uid(),reviewed_at=now() where id=p_request;
 if p_approve then
   insert into public.wallet_entries(agency_id,amount_eur,entry_type,note,topup_request_id)
   values(r.agency_id,r.amount_eur,'topup','Virement vérifié : '||r.transfer_reference,r.id);
 end if;
 insert into public.finance_audit(event,entity_id,details)
 values('topup_review',r.id,jsonb_build_object('approved',p_approve,'amount_eur',r.amount_eur));
end $$;
revoke all on function public.admin_review_topup(uuid,boolean) from public;
grant execute on function public.admin_review_topup(uuid,boolean) to authenticated;

create or replace function public.admin_wallet_entry(p_agency uuid,p_amount numeric,p_kind text,p_note text,p_booking uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare available numeric; ident uuid; booking_rec public.booking_requests; refunded numeric;
begin
 if not public.is_admin() then raise exception 'Admin requis'; end if;
 if p_amount is null or p_amount=0 or p_amount<>round(p_amount,2) or abs(p_amount)>1000000
   then raise exception 'Montant incorrect'; end if;
 if length(trim(coalesce(p_note,'')))<4 then raise exception 'Justificatif requis'; end if;
 if p_kind not in ('booking_debit','refund','manual_adjustment') then raise exception 'Type invalide'; end if;
 if (p_kind='booking_debit' and (p_amount>=0 or p_booking is null)) or
    (p_kind='refund' and (p_amount<=0 or p_booking is null)) or
    (p_kind='manual_adjustment' and p_booking is not null) then raise exception 'Sens ou référence incorrecte'; end if;
 perform 1 from public.agencies where id=p_agency for update;
 if not found then raise exception 'Agence inconnue'; end if;
 if p_booking is not null then
  select * into booking_rec from public.booking_requests where id=p_booking;
  if not found or booking_rec.agency_id<>p_agency then raise exception 'Réservation/agence non correspondante'; end if;
  if p_kind='booking_debit' and (booking_rec.status<>'confirmed' or -p_amount<>booking_rec.total_eur)
    then raise exception 'Réservation non validée ou montant différent'; end if;
  if p_kind='refund' then
    if not exists(select 1 from public.wallet_entries where booking_id=p_booking and entry_type='booking_debit')
      then raise exception 'Débit d’origine manquant'; end if;
    select coalesce(sum(amount_eur),0) into refunded from public.wallet_entries where booking_id=p_booking and entry_type='refund';
    if refunded+p_amount>booking_rec.total_eur then raise exception 'Remboursement total supérieur au débit'; end if;
  end if;
 end if;
 select coalesce(sum(amount_eur),0) into available from public.wallet_entries where agency_id=p_agency;
 if available+p_amount<0 then raise exception 'Solde insuffisant'; end if;
 insert into public.wallet_entries(agency_id,amount_eur,entry_type,note,booking_id)
 values(p_agency,p_amount,p_kind,trim(p_note),p_booking) returning id into ident;
 insert into public.finance_audit(event,entity_id,details) values('wallet_entry',ident,jsonb_build_object('agency_id',p_agency,'amount_eur',p_amount,'kind',p_kind));
 return ident;
end $$;
revoke all on function public.admin_wallet_entry(uuid,numeric,text,text,uuid) from public;
grant execute on function public.admin_wallet_entry(uuid,numeric,text,text,uuid) to authenticated;

create or replace function public.admin_create_payable(p_beneficiary text,p_type text,p_amount numeric,p_reference text,p_due date default null,p_booking uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare ident uuid;
begin
 if not public.is_admin() then raise exception 'Admin requis'; end if;
 if p_type not in ('dmc','hotel','api') or length(trim(coalesce(p_beneficiary,'')))<3
  or length(trim(coalesce(p_reference,'')))<3 or p_amount<=0 or p_amount<>round(p_amount,2)
  then raise exception 'Données de règlement invalides'; end if;
 insert into public.supplier_payables(beneficiary_name,beneficiary_type,amount_eur,reference,due_date,booking_id)
 values(trim(p_beneficiary),p_type,p_amount,trim(p_reference),p_due,p_booking) returning id into ident;
 insert into public.finance_audit(event,entity_id) values('payable_created',ident);
 return ident;
end $$;
revoke all on function public.admin_create_payable(text,text,numeric,text,date,uuid) from public;
grant execute on function public.admin_create_payable(text,text,numeric,text,date,uuid) to authenticated;

create or replace function public.admin_payable_action(p_id uuid,p_action text,p_bank_ref text default null)
returns void language plpgsql security definer set search_path=public as $$
declare r public.supplier_payables;
begin
 if not public.is_admin() then raise exception 'Admin requis'; end if;
 select * into r from public.supplier_payables where id=p_id for update;
 if not found then raise exception 'Règlement introuvable'; end if;
 if p_action='approve' and r.status='draft' then
  update public.supplier_payables set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_id;
 elsif p_action='paid' and r.status='approved' and length(trim(coalesce(p_bank_ref,'')))>=4 then
  update public.supplier_payables set status='paid',bank_reference=trim(p_bank_ref),paid_by=auth.uid(),paid_at=now() where id=p_id;
 elsif p_action='cancel' and r.status in ('draft','approved') then
  update public.supplier_payables set status='cancelled' where id=p_id;
 else raise exception 'Transition interdite ou référence bancaire manquante'; end if;
 insert into public.finance_audit(event,entity_id,details) values('payable_'||p_action,p_id,jsonb_build_object('bank_reference',p_bank_ref));
end $$;
revoke all on function public.admin_payable_action(uuid,text,text) from public;
grant execute on function public.admin_payable_action(uuid,text,text) to authenticated;

commit;
