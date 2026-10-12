-- Dossier d'identité des livreurs : état civil, pièce d'identité, permis, photos.
-- Données personnelles sensibles : lecture réservée à l'administrateur et au superviseur (et au livreur pour son propre dossier),
-- toute modification est journalisée, les images sont de petits JPEG/PNG (data-URL) de 400 Ko maximum.

create table public.livreur_dossiers (
  livreur_id uuid primary key references public.livreurs(id) on delete cascade,
  org_id uuid not null references public.organisations(id) on delete cascade,
  date_naissance date,
  adresse text,
  contact_urgence_nom text,
  contact_urgence_tel text,
  garant_nom text,
  garant_tel text,
  piece_type text check (piece_type in ('cni','passeport','attestation','carte_consulaire')),
  piece_numero text,
  piece_expire date,
  permis_numero text,
  permis_categorie text,
  permis_expire date,
  consent_le timestamptz,                       -- accord du livreur pour la conservation de ses documents
  maj_le timestamptz not null default now(),
  maj_par uuid
);

create table public.livreur_fichiers (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id) on delete cascade,
  kind text not null check (kind in ('photo','piece_recto','piece_verso','permis')),
  fichier text not null check (fichier ~ '^data:image/(jpeg|png);base64,[A-Za-z0-9+/=]+$' and length(fichier) <= 400000),
  miniature text check (miniature is null or (miniature ~ '^data:image/(jpeg|png);base64,[A-Za-z0-9+/=]+$' and length(miniature) <= 20000)),
  maj_le timestamptz not null default now(),
  unique (livreur_id, kind)
);
create index on public.livreur_fichiers (org_id);

alter table public.livreur_dossiers enable row level security;
alter table public.livreur_fichiers enable row level security;

create policy dossiers_select on public.livreur_dossiers for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur')) or livreur_id = (select app.livreur_id())));
create policy dossiers_write on public.livreur_dossiers for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')));
create policy fichiers_select on public.livreur_fichiers for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur')) or livreur_id = (select app.livreur_id())));
create policy fichiers_write on public.livreur_fichiers for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')));

grant select, insert, update, delete on public.livreur_dossiers, public.livreur_fichiers to authenticated;

-- L'organisation et l'auteur ne se choisissent pas côté client.
create or replace function app.trg_dossier() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid;
begin
  select org_id into v_org from public.livreurs where id = new.livreur_id;
  if v_org is null or v_org <> app.org() then raise exception 'Livreur inconnu'; end if;
  new.org_id := v_org; new.maj_le := now();
  if tg_table_name = 'livreur_dossiers' then new.maj_par := auth.uid(); end if;
  return new;
end $f$;
create trigger dossier_org before insert or update on public.livreur_dossiers for each row execute function app.trg_dossier();
create trigger fichier_org before insert or update on public.livreur_fichiers for each row execute function app.trg_dossier();

-- Journal : on trace l'action, jamais le contenu des images.
create or replace function app.trg_audit_dossier() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v jsonb := to_jsonb(coalesce(new, old)); v_nom text;
begin
  select nom into v_nom from public.livreurs where id = (v ->> 'livreur_id')::uuid;
  perform app.log((v ->> 'org_id')::uuid, tg_op || ' ' || tg_table_name,
    coalesce(v_nom, '') || case when v ? 'kind' then ' · ' || (v ->> 'kind') else '' end);
  return coalesce(new, old);
end $f$;
create trigger audit_dossiers after insert or update or delete on public.livreur_dossiers for each row execute function app.trg_audit_dossier();
create trigger audit_fichiers after insert or update or delete on public.livreur_fichiers for each row execute function app.trg_audit_dossier();

-- Dossier complet : état civil minimal, pièce valide recto/verso, permis valide, photo, contact d'urgence, accord du livreur.
create or replace function app.dossier_complet(p_livreur uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce((
    select d.piece_type is not null and coalesce(btrim(d.piece_numero), '') <> '' and d.piece_expire > current_date
       and coalesce(btrim(d.permis_numero), '') <> '' and d.permis_expire > current_date
       and coalesce(btrim(d.contact_urgence_tel), '') <> '' and d.consent_le is not null
       and (select count(*) from public.livreur_fichiers f where f.livreur_id = d.livreur_id and f.kind in ('photo','piece_recto','piece_verso','permis')) = 4
    from public.livreur_dossiers d where d.livreur_id = p_livreur), false)
$f$;

-- Option de l'organisation : refuser toute affectation à un livreur dont le dossier n'est pas complet.
create or replace function app.trg_exiger_dossier() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  if coalesce((select (config ->> 'dossier_obligatoire')::boolean from public.organisations where id = new.org_id), false)
     and not app.dossier_complet(new.livreur_id) then
    raise exception 'Dossier du livreur incomplet ou expiré : pièce d''identité, permis, photos et accord sont requis';
  end if;
  return new;
end $f$;
create trigger livraison_dossier before insert on public.livraisons for each row execute function app.trg_exiger_dossier();

-- Rappels d'échéance (30 jours) lisibles par l'administrateur et le superviseur.
create or replace function public.dossiers_a_surveiller() returns table (livreur_id uuid, nom text, probleme text)
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
  return query
    select l.id, l.nom, case
        when d.livreur_id is null then 'Dossier non renseigné'
        when d.piece_expire is null or d.piece_expire <= current_date then 'Pièce d''identité expirée ou absente'
        when d.permis_expire is null or d.permis_expire <= current_date then 'Permis expiré ou absent'
        when d.piece_expire <= current_date + 30 then 'Pièce d''identité expire dans moins de 30 jours'
        when d.permis_expire <= current_date + 30 then 'Permis expire dans moins de 30 jours'
        when not app.dossier_complet(l.id) then 'Dossier incomplet (photos, contact, accord)' end
    from public.livreurs l left join public.livreur_dossiers d on d.livreur_id = l.id
    where l.org_id = app.org()
      and (not app.dossier_complet(l.id) or d.piece_expire <= current_date + 30 or d.permis_expire <= current_date + 30);
end $f$;
revoke all on function public.dossiers_a_surveiller() from public, anon;
grant execute on function public.dossiers_a_surveiller() to authenticated;
