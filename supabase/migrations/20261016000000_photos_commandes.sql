-- Photos / captures d'écran jointes à une commande (article montré par le client sur WhatsApp, etc.).
-- Petites images JPEG/PNG (data-URL, 300 Ko max), 8 par commande. Lecture : équipe, vendeur propriétaire, livreur affecté.
-- Écriture uniquement par les fonctions ci-dessous.

create table public.commande_photos (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid not null references public.commandes(id) on delete cascade,
  fichier text not null check (fichier ~ '^data:image/(jpeg|png);base64,[A-Za-z0-9+/=]+$' and length(fichier) <= 300000),
  ts timestamptz not null default now(),
  par_nom text
);
create index on public.commande_photos (commande_id);
alter table public.commande_photos enable row level security;
create policy photos_select on public.commande_photos for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur', 'commercial', 'preparateur'))
  or exists (select 1 from public.commandes c where c.id = commande_id and c.vendeur_id is not null and c.vendeur_id = (select app.vendeur_id()))
  or app.livreur_voit_commande(commande_id)));
grant select on public.commande_photos to authenticated;

create or replace function app.peut_photo(p_commande uuid, p_ecriture boolean) returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from public.commandes c where c.id = p_commande and c.org_id = app.org() and (
    app.has_role('admin', 'superviseur', 'commercial')
    or (c.vendeur_id is not null and c.vendeur_id = app.vendeur_id())))
$f$;

create or replace function public.ajouter_photo_commande(p_commande uuid, p_fichier text) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.commandes%rowtype; v_id bigint;
begin
  select * into c from public.commandes where id = p_commande and org_id = v_org;
  if not found then raise exception 'Commande introuvable'; end if;
  if not app.peut_photo(p_commande, true) then perform app.deny(); end if;
  if c.statut in ('livree', 'annulee', 'retour_recu') then raise exception 'Commande terminée : photo impossible'; end if;
  if (select count(*) from public.commande_photos where commande_id = p_commande) >= 8 then raise exception 'Maximum 8 photos par commande'; end if;
  insert into public.commande_photos(org_id, commande_id, fichier, par_nom)
    values (v_org, p_commande, p_fichier, (select nom from public.membres where user_id = auth.uid())) returning id into v_id;
  perform app.log(v_org, 'Photo ajoutée à la commande', c.numero);
  return v_id;
end $f$;

create or replace function public.retirer_photo_commande(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $f$
declare p public.commande_photos%rowtype; c public.commandes%rowtype;
begin
  select * into p from public.commande_photos where id = p_id and org_id = app.org();
  if not found then raise exception 'Photo introuvable'; end if;
  select * into c from public.commandes where id = p.commande_id;
  if not app.peut_photo(p.commande_id, true) then perform app.deny(); end if;
  if c.statut not in ('brouillon', 'attente', 'confirmee') and not app.has_role('admin', 'superviseur', 'commercial') then raise exception 'Commande déjà en préparation : photo non modifiable'; end if;
  delete from public.commande_photos where id = p_id;
  perform app.log(p.org_id, 'Photo retirée de la commande', c.numero);
end $f$;

revoke all on function public.ajouter_photo_commande(uuid, text), public.retirer_photo_commande(bigint) from public, anon;
grant execute on function public.ajouter_photo_commande(uuid, text), public.retirer_photo_commande(bigint) to authenticated;
