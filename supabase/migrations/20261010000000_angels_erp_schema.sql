-- =====================================================================
-- ANGEL'S GROUP ERP — schéma Supabase (V1 : livraisons à moto)
-- Principes :
--   * isolation par organisation (org_id) sur toutes les tables ;
--   * lecture protégée par RLS, selon le profil de l'utilisateur ;
--   * AUCUNE écriture métier directe : les opérations sensibles
--     (statuts, affectation, encaissement, reversement, stock, règlements)
--     passent par des fonctions RPC qui contrôlent le profil et les règles ;
--   * journaux en « ajout seul » (fonds, audit, historique, GPS).
-- =====================================================================

create schema if not exists app;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
create table public.organisations (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  whatsapp text,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.membres (
  user_id uuid primary key references auth.users(id) on delete cascade,
  org_id uuid not null references public.organisations(id) on delete cascade,
  role text not null check (role in ('admin','direction','superviseur','commercial','preparateur','caissier','livreur','vendeur')),
  nom text not null,
  actif boolean not null default true,
  livreur_id uuid,
  vendeur_id uuid,
  created_at timestamptz not null default now()
);

create table public.compteurs (
  org_id uuid primary key references public.organisations(id) on delete cascade,
  cmd int not null default 0,
  inc int not null default 0
);

create table public.zones (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  nom text not null,
  frais int not null check (frais >= 0),
  delai_min int not null check (delai_min > 0),
  unique (org_id, nom)
);

create table public.motos (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  immat text not null,
  modele text,
  km int not null default 0,
  prochain_km int not null default 1000,
  statut text not null default 'disponible' check (statut in ('disponible','affectee','panne','immobilisee')),
  unique (org_id, immat)
);

create table public.livreurs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  nom text not null,
  tel text,
  zone text,
  moto_id uuid references public.motos(id) on delete set null,
  statut text not null default 'disponible' check (statut in ('disponible','indisponible')),
  gps_consent boolean not null default false,
  remu jsonb,                                   -- {type: fixe|pct|mixte, fixe, pct} ; null = défaut de l'organisation
  created_at timestamptz not null default now()
);

create table public.vendeurs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  nom text not null,
  tel text,
  commission_pct numeric(5,2) not null default 0 check (commission_pct between 0 and 100),
  created_at timestamptz not null default now()
);

alter table public.membres
  add constraint membres_livreur_fk foreign key (livreur_id) references public.livreurs(id) on delete set null,
  add constraint membres_vendeur_fk foreign key (vendeur_id) references public.vendeurs(id) on delete set null;

create table public.produits (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  code text not null,
  nom text not null,
  prix int not null check (prix >= 0),
  stock int not null default 0 check (stock >= 0),
  seuil int not null default 10,
  actif boolean not null default true,
  unique (org_id, code)
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  nom text not null,
  tel text not null,
  tel2 text,
  note text,
  vendeur_id uuid references public.vendeurs(id) on delete set null,   -- client appartenant à un vendeur partenaire
  created_at timestamptz not null default now()
);
create index on public.clients (org_id, tel);

create table public.adresses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  libelle text not null default 'Adresse',
  zone text not null,
  quartier text,
  repere text,
  instructions text,
  lat numeric(9,6) check (lat between -90 and 90),
  lng numeric(9,6) check (lng between -180 and 180),
  gps_src text,
  gps_ts timestamptz,
  gps_acc int,
  defaut boolean not null default false
);
create index on public.adresses (client_id);

create table public.commandes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  numero text not null,
  date timestamptz not null default now(),
  vendeur_id uuid references public.vendeurs(id),
  vendeur_encaisse boolean not null default false,       -- articles déjà payés au vendeur
  client_id uuid not null references public.clients(id),
  adresse_id uuid references public.adresses(id) on delete set null,
  adr jsonb not null,                                    -- copie de l'adresse au moment de la commande (historique)
  frais int not null default 0 check (frais >= 0),
  remise int not null default 0 check (remise >= 0),
  montant_produits int not null default 0,
  total int not null default 0,
  paiement text not null check (paiement in ('avance','livraison','partiel')),
  mode text,
  priorite text not null default 'normale' check (priorite in ('normale','urgente','programmee')),
  canal text,
  obs text,
  statut text not null default 'brouillon' check (statut in ('brouillon','attente','confirmee','preparation','prete','affectee','en_cours','livree','echouee','retour_cours','retour_recu','annulee')),
  stock_sorti boolean not null default false,
  cree_par uuid,
  unique (org_id, numero)
);
create index on public.commandes (org_id, statut);
create index on public.commandes (vendeur_id);
create index on public.commandes (client_id);

create table public.commande_lignes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid not null references public.commandes(id) on delete cascade,
  produit_id uuid references public.produits(id),        -- null = article d'un vendeur tiers
  desig text,
  qte int not null check (qte > 0),
  pu int not null check (pu >= 0),
  check (produit_id is not null or coalesce(desig,'') <> '')
);
create index on public.commande_lignes (commande_id);

create table public.commande_historique (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid not null references public.commandes(id) on delete cascade,
  ts timestamptz not null default now(),
  de text,
  a text not null,
  par_user uuid,
  par_nom text,
  note text
);
create index on public.commande_historique (commande_id);

create table public.livraisons (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid not null references public.commandes(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id),
  moto_id uuid references public.motos(id),
  tentative int not null default 1,
  statut text not null default 'affectee' check (statut in ('affectee','acceptee','en_cours','livree','echouee','refusee','reaffectee','annulee')),
  montant_attendu int not null default 0,
  affectee_at timestamptz not null default now(),
  accept_at timestamptz,
  collecte_at timestamptz,
  nb_colis int,
  etat_colis text,
  depart_at timestamptz,
  fin_at timestamptz,
  montant_encaisse int,
  mode text,
  recu_par text,
  motif text,
  motif_echec text,
  obs text,
  ecart int,
  ecart_statut text check (ecart_statut in ('a_valider','valide','rejete')),
  ecart_note text,
  ecart_decision text,
  ecart_par uuid,
  essais_code int not null default 0,
  gps_confirm_lat numeric(9,6),
  gps_confirm_lng numeric(9,6)
);
create index on public.livraisons (org_id, statut);
create index on public.livraisons (livreur_id, statut);
create index on public.livraisons (commande_id);

-- Code de confirmation client : table séparée, jamais lisible par le livreur ni le vendeur.
create table public.livraison_codes (
  livraison_id uuid primary key references public.livraisons(id) on delete cascade,
  org_id uuid not null references public.organisations(id) on delete cascade,
  code text not null
);

create table public.positions_gps (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organisations(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id) on delete cascade,
  livraison_id uuid references public.livraisons(id) on delete set null,
  lat numeric(9,6) not null,
  lng numeric(9,6) not null,
  acc int,
  ts timestamptz not null default now()
);
create index on public.positions_gps (livreur_id, ts desc);

create table public.fonds (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  type text not null check (type in ('acompte','encaissement','reversement')),
  livreur_id uuid references public.livreurs(id),
  livraison_id uuid references public.livraisons(id),
  commande_id uuid references public.commandes(id),
  montant int not null check (montant > 0),
  mode text,
  note text,
  ts timestamptz not null default now(),
  par uuid,
  par_nom text
);
create index on public.fonds (livreur_id, type);
create index on public.fonds (commande_id);

create table public.paiements_livreurs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id),
  type text not null check (type in ('commission','avance')),
  montant int not null check (montant > 0),
  ts timestamptz not null default now(),
  par uuid default auth.uid()
);

create table public.depenses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id),
  commande_id uuid references public.commandes(id),
  nature text not null,
  montant int not null check (montant > 0),
  ts timestamptz not null default now(),
  par uuid default auth.uid()
);

create table public.reglements_vendeurs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  vendeur_id uuid not null references public.vendeurs(id),
  montant int not null check (montant > 0),
  mode text,
  note text,
  ts timestamptz not null default now(),
  par uuid,
  par_nom text
);

create table public.incidents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  ref text not null,
  ts timestamptz not null default now(),
  cat text not null,
  commande_id uuid references public.commandes(id),
  par_user uuid not null default auth.uid(),
  par_nom text,
  descr text not null,
  statut text not null default 'ouvert' check (statut in ('ouvert','en traitement','résolu')),
  decision text,
  responsable uuid,
  unique (org_id, ref)
);

create table public.retours (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid not null references public.commandes(id),
  ts timestamptz not null default now(),
  motif text,
  etat text,
  decision text,
  qtes jsonb,
  par uuid,
  par_nom text
);

create table public.stock_mouvements (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organisations(id) on delete cascade,
  produit_id uuid not null references public.produits(id),
  ts timestamptz not null default now(),
  type text not null,
  qte int not null,
  ref text,
  par uuid,
  par_nom text
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  org_id uuid references public.organisations(id) on delete cascade,
  ts timestamptz not null default now(),
  user_id uuid,
  user_nom text,
  role text,
  action text not null,
  detail text
);
create index on public.audit_log (org_id, ts desc);

-- Liens du portail client (géopositionnement de l'adresse) : accès uniquement via RPC.
create table public.portail_liens (
  token text primary key default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  org_id uuid not null references public.organisations(id) on delete cascade,
  adresse_id uuid not null references public.adresses(id) on delete cascade,
  ref text,
  expires_at timestamptz not null default now() + interval '30 days',
  essais int not null default 0,
  used_at timestamptz
);

-- ---------------------------------------------------------------------
-- 2. Fonctions d'aide (schéma privé « app », non exposé par l'API)
-- ---------------------------------------------------------------------
create or replace function app.org() returns uuid
language sql stable security definer set search_path = '' as $f$
  select org_id from public.membres where user_id = auth.uid() and actif
$f$;

create or replace function app.role() returns text
language sql stable security definer set search_path = '' as $f$
  select role from public.membres where user_id = auth.uid() and actif
$f$;

create or replace function app.livreur_id() returns uuid
language sql stable security definer set search_path = '' as $f$
  select livreur_id from public.membres where user_id = auth.uid() and actif and role = 'livreur'
$f$;

create or replace function app.vendeur_id() returns uuid
language sql stable security definer set search_path = '' as $f$
  select vendeur_id from public.membres where user_id = auth.uid() and actif and role = 'vendeur'
$f$;

create or replace function app.has_role(variadic r text[]) returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce((select role = any(r) from public.membres where user_id = auth.uid() and actif), false)
$f$;

-- Le livreur voit les commandes de ses missions actives (et terminées depuis moins de 24 h).
create or replace function app.livreur_voit_commande(p_cid uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (
    select 1 from public.livraisons l
    where l.commande_id = p_cid and l.livreur_id = app.livreur_id()
      and (l.statut in ('affectee','acceptee','en_cours') or l.fin_at > now() - interval '24 hours'))
$f$;

create or replace function app.livreur_voit_client(p_client uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (
    select 1 from public.livraisons l join public.commandes c on c.id = l.commande_id
    where c.client_id = p_client and l.livreur_id = app.livreur_id()
      and (l.statut in ('affectee','acceptee','en_cours') or l.fin_at > now() - interval '24 hours'))
$f$;

create or replace function app.livreur_voit_adresse(p_adr uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (
    select 1 from public.livraisons l join public.commandes c on c.id = l.commande_id
    where c.adresse_id = p_adr and l.livreur_id = app.livreur_id()
      and (l.statut in ('affectee','acceptee','en_cours') or l.fin_at > now() - interval '24 hours'))
$f$;

create or replace function app.livreur_moto() returns uuid
language sql stable security definer set search_path = '' as $f$
  select moto_id from public.livreurs where id = app.livreur_id()
$f$;

create or replace function app.log(p_org uuid, p_action text, p_detail text default '') returns void
language plpgsql security definer set search_path = '' as $f$
declare v_nom text; v_role text;
begin
  select nom, role into v_nom, v_role from public.membres where user_id = auth.uid();
  insert into public.audit_log(org_id, user_id, user_nom, role, action, detail)
  values (p_org, auth.uid(), coalesce(v_nom, 'Public (portail)'), coalesce(v_role, 'anonyme'), p_action, coalesce(p_detail, ''));
end $f$;

create or replace function app.deny() returns void
language plpgsql set search_path = '' as $f$
begin raise exception 'Accès refusé pour votre profil' using errcode = '42501'; end $f$;

create or replace function app.next_num(p_org uuid) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_n int;
begin
  insert into public.compteurs(org_id, cmd) values (p_org, 1)
  on conflict (org_id) do update set cmd = public.compteurs.cmd + 1
  returning cmd into v_n;
  return 'CMD-' || extract(year from now())::int || '-' || lpad(v_n::text, 4, '0');
end $f$;

-- Machine à états des commandes
create or replace function app.transition_ok(p_de text, p_a text) returns boolean
language sql immutable set search_path = '' as $f$
  select coalesce((('{
    "brouillon":["attente","confirmee","annulee"],
    "attente":["confirmee","annulee"],
    "confirmee":["preparation","annulee"],
    "preparation":["prete","annulee"],
    "prete":["affectee","annulee"],
    "affectee":["en_cours","echouee","prete","annulee"],
    "en_cours":["livree","echouee"],
    "livree":[],
    "echouee":["prete","retour_cours","annulee"],
    "retour_cours":["retour_recu"],
    "retour_recu":[],
    "annulee":[]}')::jsonb -> p_de) ? p_a, false)
$f$;

create or replace function app.set_statut(p_cid uuid, p_to text, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $f$
begin
  perform set_config('app.note', coalesce(p_note, ''), true);
  update public.commandes set statut = p_to where id = p_cid;
end $f$;

create or replace function app.solde_commande(p_cid uuid) returns int
language sql stable security definer set search_path = '' as $f$
  select greatest(0, c.total - coalesce((select sum(f.montant) from public.fonds f
        where f.commande_id = c.id and f.type in ('acompte','encaissement')), 0))::int
  from public.commandes c where c.id = p_cid
$f$;

create or replace function app.stock_mvt(p_org uuid, p_prod uuid, p_qte int, p_type text, p_ref text) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  update public.produits set stock = stock + p_qte where id = p_prod and org_id = p_org;
  insert into public.stock_mouvements(org_id, produit_id, type, qte, ref, par, par_nom)
  values (p_org, p_prod, p_type, p_qte, p_ref, auth.uid(),
          coalesce((select nom from public.membres where user_id = auth.uid()), 'Système'));
end $f$;

-- Position GPS d'une adresse (client, personnel) : met à jour la fiche et les commandes non terminées
create or replace function app.maj_position(p_org uuid, p_adr uuid, p_lat numeric, p_lng numeric, p_src text, p_acc int, p_note text)
returns void language plpgsql security definer set search_path = '' as $f$
declare v_note text := nullif(left(btrim(coalesce(p_note, '')), 200), '');
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Coordonnées invalides';
  end if;
  update public.adresses set lat = round(p_lat, 6), lng = round(p_lng, 6), gps_src = p_src, gps_ts = now(),
         gps_acc = p_acc,
         instructions = case when v_note is null then instructions
                             else coalesce(nullif(instructions, '') || ' — ', '') || v_note end
  where id = p_adr and org_id = p_org;
  if not found then raise exception 'Adresse introuvable'; end if;
  update public.commandes c
     set adr = c.adr || jsonb_build_object('gps', jsonb_build_object('lat', round(p_lat, 6), 'lng', round(p_lng, 6)), 'gps_src', p_src)
   where c.adresse_id = p_adr and c.org_id = p_org
     and c.statut not in ('livree','annulee','retour_recu');
end $f$;

-- ---------------------------------------------------------------------
-- 3. Triggers
-- ---------------------------------------------------------------------
create or replace function app.trg_commande_statut() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  if new.statut is distinct from old.statut then
    if coalesce(current_setting('app.force', true), '') <> '1' and not app.transition_ok(old.statut, new.statut) then
      raise exception 'Transition interdite : % -> %', old.statut, new.statut using errcode = 'P0001';
    end if;
    insert into public.commande_historique(org_id, commande_id, de, a, par_user, par_nom, note)
    values (new.org_id, new.id, old.statut, new.statut, auth.uid(),
            coalesce((select nom from public.membres where user_id = auth.uid()), 'Système'),
            coalesce(current_setting('app.note', true), ''));
  end if;
  return new;
end $f$;
create trigger commande_statut before update on public.commandes
  for each row execute function app.trg_commande_statut();

create or replace function app.trg_append_only() returns trigger
language plpgsql set search_path = '' as $f$
begin
  if tg_op = 'DELETE' and tg_table_name = 'positions_gps' and coalesce(current_setting('app.purge', true), '') = '1' then
    return old;
  end if;
  raise exception 'La table % est en ajout seul (modification interdite)', tg_table_name using errcode = 'P0001';
end $f$;
create trigger fonds_ajout_seul before update or delete on public.fonds for each row execute function app.trg_append_only();
create trigger audit_ajout_seul before update or delete on public.audit_log for each row execute function app.trg_append_only();
create trigger histo_ajout_seul before update or delete on public.commande_historique for each row execute function app.trg_append_only();
create trigger gps_ajout_seul before update or delete on public.positions_gps for each row execute function app.trg_append_only();
create trigger stock_ajout_seul before update or delete on public.stock_mouvements for each row execute function app.trg_append_only();

-- Le suivi GPS ne se garde pas indéfiniment (cahier des charges §6.4)
create or replace function app.purge_gps(p_jours int default 30) returns int
language plpgsql security definer set search_path = '' as $f$
declare v_n int;
begin
  perform set_config('app.purge', '1', true);
  delete from public.positions_gps where ts < now() - make_interval(days => p_jours);
  get diagnostics v_n = row_count;
  perform set_config('app.purge', '', true);
  return v_n;
end $f$;

-- Traçabilité des référentiels modifiés directement
create or replace function app.trg_audit() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v jsonb := to_jsonb(coalesce(new, old));
begin
  perform app.log((v->>'org_id')::uuid, tg_op || ' ' || tg_table_name, coalesce(v->>'nom', v->>'immat', v->>'code', ''));
  return coalesce(new, old);
end $f$;
create trigger audit_clients after insert or update or delete on public.clients for each row execute function app.trg_audit();
create trigger audit_produits after insert or update or delete on public.produits for each row execute function app.trg_audit();
create trigger audit_zones after insert or update or delete on public.zones for each row execute function app.trg_audit();
create trigger audit_livreurs after insert or update or delete on public.livreurs for each row execute function app.trg_audit();
create trigger audit_motos after insert or update or delete on public.motos for each row execute function app.trg_audit();
create trigger audit_vendeurs after insert or update or delete on public.vendeurs for each row execute function app.trg_audit();
create trigger audit_membres after update or delete on public.membres for each row execute function app.trg_audit();

-- ---------------------------------------------------------------------
-- 4. RPC métier (SECURITY DEFINER, contrôle du profil dans chaque fonction)
-- ---------------------------------------------------------------------

-- Insertion interne d'une commande (totaux recalculés côté serveur)
create or replace function app.insert_commande(
  p_org uuid, p_vendeur uuid, p_client uuid, p_adresse uuid, p_lignes jsonb,
  p_frais int, p_remise int, p_paiement text, p_acompte int, p_mode text,
  p_priorite text, p_canal text, p_obs text, p_vendeur_encaisse boolean) returns uuid
language plpgsql security definer set search_path = '' as $f$
declare
  v_id uuid := gen_random_uuid(); v_a record; v_prods int; v_total int; v_ac int := 0;
begin
  select a.* into v_a from public.adresses a where a.id = p_adresse and a.org_id = p_org and a.client_id = p_client;
  if not found then raise exception 'Adresse introuvable pour ce client'; end if;
  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then
    raise exception 'La commande doit contenir au moins un article';
  end if;
  if exists (select 1 from jsonb_to_recordset(p_lignes) as x(produit_id uuid, desig text, qte int, pu int)
             left join public.produits pr on pr.id = x.produit_id and pr.org_id = p_org
             where x.qte is null or x.qte <= 0 or coalesce(x.pu, pr.prix, 0) < 0
                or (x.produit_id is null and coalesce(x.desig, '') = '')
                or (x.produit_id is not null and pr.id is null)) then
    raise exception 'Ligne de commande invalide';
  end if;
  select coalesce(sum(x.qte * coalesce(x.pu, pr.prix)), 0) into v_prods
    from jsonb_to_recordset(p_lignes) as x(produit_id uuid, desig text, qte int, pu int)
    left join public.produits pr on pr.id = x.produit_id;
  v_total := greatest(0, v_prods + coalesce(p_frais, 0) - coalesce(p_remise, 0));
  insert into public.commandes(id, org_id, numero, vendeur_id, vendeur_encaisse, client_id, adresse_id, adr, frais, remise,
        montant_produits, total, paiement, mode, priorite, canal, obs, statut, cree_par)
  values (v_id, p_org, app.next_num(p_org), p_vendeur, coalesce(p_vendeur_encaisse, false), p_client, p_adresse,
        jsonb_build_object('id', v_a.id, 'libelle', v_a.libelle, 'zone', v_a.zone, 'quartier', v_a.quartier,
          'repere', v_a.repere, 'instructions', v_a.instructions,
          'gps', case when v_a.lat is null then null else jsonb_build_object('lat', v_a.lat, 'lng', v_a.lng) end,
          'gps_src', v_a.gps_src),
        greatest(0, coalesce(p_frais, 0)), greatest(0, coalesce(p_remise, 0)), v_prods, v_total, p_paiement, p_mode,
        coalesce(p_priorite, 'normale'), p_canal, p_obs, 'brouillon', auth.uid());
  insert into public.commande_lignes(org_id, commande_id, produit_id, desig, qte, pu)
    select p_org, v_id, x.produit_id, x.desig, x.qte, coalesce(x.pu, pr.prix)
    from jsonb_to_recordset(p_lignes) as x(produit_id uuid, desig text, qte int, pu int)
    left join public.produits pr on pr.id = x.produit_id;
  insert into public.commande_historique(org_id, commande_id, de, a, par_user, par_nom, note)
    values (p_org, v_id, null, 'brouillon', auth.uid(),
            coalesce((select nom from public.membres where user_id = auth.uid()), 'Système'), 'Création');
  v_ac := case p_paiement when 'avance' then v_total when 'partiel' then least(greatest(coalesce(p_acompte, 0), 0), v_total) else 0 end;
  if v_ac > 0 then
    insert into public.fonds(org_id, type, commande_id, montant, mode, par, par_nom)
    values (p_org, 'acompte', v_id, v_ac, p_mode, auth.uid(), coalesce((select nom from public.membres where user_id = auth.uid()), 'Système'));
  end if;
  return v_id;
end $f$;

-- Commande saisie par le personnel
create or replace function public.creer_commande(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_id uuid; v_num text;
begin
  if not app.has_role('admin', 'superviseur', 'commercial') then perform app.deny(); end if;
  if p->>'paiement' not in ('avance', 'livraison', 'partiel') then raise exception 'Mode de paiement invalide'; end if;
  v_id := app.insert_commande(v_org, null, (p->>'client_id')::uuid, (p->>'adresse_id')::uuid, p->'lignes',
            coalesce((p->>'frais')::int, 0), coalesce((p->>'remise')::int, 0), p->>'paiement', coalesce((p->>'acompte')::int, 0),
            p->>'mode', p->>'priorite', coalesce(p->>'canal', 'Téléphone'), p->>'obs', false);
  if coalesce((p->>'confirmer')::boolean, false) then perform app.set_statut(v_id, 'confirmee', 'Confirmation à la création'); end if;
  select numero into v_num from public.commandes where id = v_id;
  perform app.log(v_org, 'Création commande', v_num);
  return jsonb_build_object('id', v_id, 'numero', v_num);
end $f$;

-- Commande déposée par un vendeur partenaire (frais calculés par le serveur selon la zone)
create or replace function public.vendeur_deposer_commande(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); v_vend uuid := app.vendeur_id(); v_cl uuid; v_ad uuid; v_z record;
  v_tel text := regexp_replace(coalesce(p#>>'{client,tel}', ''), '\s', '', 'g'); v_lignes jsonb; v_prods int;
  v_paye boolean := coalesce(p->>'pay', 'livraison') = 'paye'; v_id uuid; v_num text;
begin
  if v_vend is null then perform app.deny(); end if;
  if coalesce(btrim(p#>>'{client,nom}'), '') = '' or v_tel = '' then raise exception 'Nom et téléphone du client requis'; end if;
  select * into v_z from public.zones where org_id = v_org and nom = p#>>'{adresse,zone}';
  if not found then raise exception 'Zone inconnue'; end if;
  if coalesce(btrim(p#>>'{adresse,quartier}'), '') = '' and coalesce(btrim(p#>>'{adresse,repere}'), '') = '' then
    raise exception 'Indiquez le quartier ou un point de repère';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('desig', btrim(x.desig), 'qte', x.qte, 'pu', x.pu)), '[]'::jsonb) into v_lignes
    from jsonb_to_recordset(p->'lignes') as x(desig text, qte int, pu int);
  if jsonb_array_length(v_lignes) = 0 or exists (select 1 from jsonb_to_recordset(v_lignes) as x(desig text, qte int, pu int)
       where coalesce(x.desig, '') = '' or x.qte is null or x.qte <= 0 or x.pu is null or x.pu < 0) then
    raise exception 'Articles invalides (désignation, quantité et prix requis)';
  end if;
  select coalesce(sum(x.qte * x.pu), 0) into v_prods from jsonb_to_recordset(v_lignes) as x(desig text, qte int, pu int);

  select c.id into v_cl from public.clients c
   where c.org_id = v_org and c.vendeur_id = v_vend and regexp_replace(c.tel, '\s', '', 'g') = v_tel limit 1;
  if v_cl is null then
    insert into public.clients(org_id, nom, tel, vendeur_id) values (v_org, btrim(p#>>'{client,nom}'), btrim(p#>>'{client,tel}'), v_vend)
    returning id into v_cl;
  end if;
  select a.id into v_ad from public.adresses a
   where a.client_id = v_cl and a.zone = v_z.nom
     and lower(coalesce(a.quartier, '')) = lower(btrim(coalesce(p#>>'{adresse,quartier}', '')))
     and lower(coalesce(a.repere, '')) = lower(btrim(coalesce(p#>>'{adresse,repere}', ''))) limit 1;
  if v_ad is null then
    insert into public.adresses(org_id, client_id, libelle, zone, quartier, repere, instructions, defaut)
    values (v_org, v_cl, 'Livraison', v_z.nom, btrim(coalesce(p#>>'{adresse,quartier}', '')), btrim(coalesce(p#>>'{adresse,repere}', '')),
            btrim(coalesce(p#>>'{adresse,instructions}', '')), not exists (select 1 from public.adresses where client_id = v_cl))
    returning id into v_ad;
  end if;
  v_id := app.insert_commande(v_org, v_vend, v_cl, v_ad, v_lignes, v_z.frais, 0,
            case when v_paye then 'partiel' else 'livraison' end, case when v_paye then v_prods else 0 end,
            case when v_paye then 'Payé au vendeur' else 'Espèces' end, 'normale', 'Vendeur partenaire', left(p->>'obs', 500), v_paye);
  perform app.set_statut(v_id, 'attente', 'Commande déposée par le vendeur');
  select numero into v_num from public.commandes where id = v_id;
  perform app.log(v_org, 'Commande vendeur déposée', v_num);
  return jsonb_build_object('id', v_id, 'numero', v_num);
end $f$;

-- Actions sur une commande : confirmer | preparer | prete | annuler | reprogrammer | organiser_retour
create or replace function public.commande_action(p_cid uuid, p_action text, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.commandes%rowtype; r record;
begin
  select * into c from public.commandes where id = p_cid and org_id = v_org for update;
  if not found then raise exception 'Commande introuvable'; end if;
  if p_action = 'confirmer' then
    if not app.has_role('admin', 'superviseur', 'commercial') then perform app.deny(); end if;
    if c.statut not in ('brouillon', 'attente') then raise exception 'Commande déjà confirmée ou clôturée'; end if;
    perform app.set_statut(p_cid, 'confirmee', 'Confirmation');
  elsif p_action = 'preparer' then
    if not app.has_role('admin', 'preparateur') then perform app.deny(); end if;
    perform app.set_statut(p_cid, 'preparation', 'Début de préparation');
  elsif p_action = 'prete' then
    if not app.has_role('admin', 'preparateur') then perform app.deny(); end if;
    if c.statut <> 'preparation' then raise exception 'La commande doit être en préparation'; end if;
    for r in select l.produit_id, l.qte, pr.nom, pr.stock from public.commande_lignes l
             join public.produits pr on pr.id = l.produit_id where l.commande_id = p_cid for update of pr loop
      if r.stock < r.qte then raise exception 'Stock insuffisant : % (% disponible, % requis)', r.nom, r.stock, r.qte; end if;
    end loop;
    for r in select produit_id, qte from public.commande_lignes where commande_id = p_cid and produit_id is not null loop
      perform app.stock_mvt(v_org, r.produit_id, -r.qte, 'sortie_commande', c.numero);
    end loop;
    update public.commandes set stock_sorti = true where id = p_cid;
    perform app.set_statut(p_cid, 'prete', 'Préparation terminée');
  elsif p_action = 'annuler' then
    if not (app.has_role('admin', 'superviseur', 'commercial')
            or (app.role() = 'vendeur' and c.vendeur_id = app.vendeur_id() and c.statut in ('attente', 'confirmee'))) then
      perform app.deny();
    end if;
    if coalesce(btrim(p_note), '') = '' then raise exception 'Motif d''annulation obligatoire'; end if;
    perform app.set_statut(p_cid, 'annulee', 'Annulée : ' || p_note);
    update public.livraisons set statut = 'annulee', fin_at = now()
      where commande_id = p_cid and statut in ('affectee', 'acceptee', 'en_cours');
    if c.stock_sorti then
      for r in select produit_id, qte from public.commande_lignes where commande_id = p_cid and produit_id is not null loop
        perform app.stock_mvt(v_org, r.produit_id, r.qte, 'annulation', c.numero);
      end loop;
      update public.commandes set stock_sorti = false where id = p_cid;
    end if;
    perform app.log(v_org, 'Annulation commande', c.numero || ' — ' || p_note);
  elsif p_action = 'reprogrammer' then
    if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
    if c.statut <> 'echouee' then raise exception 'Seule une livraison échouée peut être reprogrammée'; end if;
    perform app.set_statut(p_cid, 'prete', 'Nouvelle tentative programmée');
    perform app.log(v_org, 'Nouvelle tentative', c.numero);
  elsif p_action = 'organiser_retour' then
    if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
    perform app.set_statut(p_cid, 'retour_cours', 'Retour du colis organisé');
    perform app.log(v_org, 'Retour organisé', c.numero);
  else
    raise exception 'Action inconnue : %', p_action;
  end if;
end $f$;

-- Correction exceptionnelle de statut (administrateur, tracée)
create or replace function public.corriger_statut(p_cid uuid, p_to text, p_motif text) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_old text; v_num text;
begin
  if not app.has_role('admin') then perform app.deny(); end if;
  if coalesce(btrim(p_motif), '') = '' then raise exception 'Justification obligatoire'; end if;
  select statut, numero into v_old, v_num from public.commandes where id = p_cid and org_id = v_org for update;
  if not found then raise exception 'Commande introuvable'; end if;
  perform set_config('app.force', '1', true);
  perform app.set_statut(p_cid, p_to, 'CORRECTION EXCEPTIONNELLE : ' || p_motif);
  perform set_config('app.force', '', true);
  perform app.log(v_org, 'Correction de statut', v_num || ' : ' || v_old || ' -> ' || p_to || ' — ' || p_motif);
end $f$;

-- Réception d'un retour
create or replace function public.reception_retour(p_cid uuid, p_qtes jsonb, p_etat text, p_decision text, p_motif text) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.commandes%rowtype; r record; v_q int;
begin
  if not app.has_role('admin', 'superviseur', 'preparateur') then perform app.deny(); end if;
  if p_decision not in ('stock', 'quarantaine', 'autre') then raise exception 'Décision invalide'; end if;
  select * into c from public.commandes where id = p_cid and org_id = v_org for update;
  if not found then raise exception 'Commande introuvable'; end if;
  perform app.set_statut(p_cid, 'retour_recu', 'Réceptionné');
  if p_decision = 'stock' and c.stock_sorti then
    for r in select id, produit_id, qte from public.commande_lignes where commande_id = p_cid and produit_id is not null loop
      v_q := least(r.qte, greatest(0, coalesce((p_qtes ->> r.id::text)::int, r.qte)));
      if v_q > 0 then perform app.stock_mvt(v_org, r.produit_id, v_q, 'retour_stock', c.numero); end if;
    end loop;
    update public.commandes set stock_sorti = false where id = p_cid;
  end if;
  insert into public.retours(org_id, commande_id, motif, etat, decision, qtes, par, par_nom)
  values (v_org, p_cid, p_motif, p_etat, p_decision, p_qtes, auth.uid(), (select nom from public.membres where user_id = auth.uid()));
  perform app.log(v_org, 'Retour réceptionné', c.numero || ' — ' || p_decision);
end $f$;

-- Affectation / réaffectation d'une livraison
create or replace function public.affecter_livraison(p_cid uuid, p_lid uuid, p_motif text default '', p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); c public.commandes%rowtype; v_lv public.livreurs%rowtype; v_mo public.motos%rowtype;
  v_old public.livraisons%rowtype; v_id uuid := gen_random_uuid(); v_code text; v_tent int;
begin
  if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
  select * into c from public.commandes where id = p_cid and org_id = v_org for update;
  if not found then raise exception 'Commande introuvable'; end if;
  select * into v_lv from public.livreurs where id = p_lid and org_id = v_org;
  if not found then raise exception 'Livreur introuvable'; end if;
  if v_lv.moto_id is not null then
    select * into v_mo from public.motos where id = v_lv.moto_id;
    if v_mo.statut not in ('disponible', 'affectee') then
      raise exception 'Moto % % : affectation impossible sans validation', v_mo.immat, v_mo.statut;
    end if;
  end if;
  if v_lv.statut <> 'disponible' and not p_force then raise exception '% est indisponible', v_lv.nom; end if;
  select * into v_old from public.livraisons where commande_id = p_cid and statut in ('affectee', 'acceptee', 'en_cours') for update;
  if found then
    if c.statut not in ('affectee', 'en_cours') then raise exception 'Réaffectation impossible dans cet état'; end if;
    if coalesce(btrim(p_motif), '') = '' then raise exception 'Motif de réaffectation obligatoire'; end if;
    if v_old.livreur_id = p_lid then raise exception 'Déjà affectée à ce livreur'; end if;
    update public.livraisons set statut = 'reaffectee', fin_at = now(), motif = p_motif where id = v_old.id;
    perform app.log(v_org, 'Réaffectation livraison', c.numero || ' -> ' || v_lv.nom || ' — ' || p_motif);
  else
    if c.statut <> 'prete' then raise exception 'La commande doit être « prête à être livrée »'; end if;
    perform app.set_statut(p_cid, 'affectee', 'Affectée à ' || v_lv.nom);
    perform app.log(v_org, 'Affectation livraison', c.numero || ' -> ' || v_lv.nom);
  end if;
  select count(*) + 1 into v_tent from public.livraisons where commande_id = p_cid and statut not in ('reaffectee', 'refusee', 'annulee');
  v_code := ((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 7))::bit(28)::int) % 9000 + 1000)::text;
  insert into public.livraisons(id, org_id, commande_id, livreur_id, moto_id, tentative, montant_attendu)
  values (v_id, v_org, p_cid, p_lid, v_lv.moto_id, v_tent, app.solde_commande(p_cid));
  insert into public.livraison_codes(livraison_id, org_id, code) values (v_id, v_org, v_code);
  return jsonb_build_object('livraison_id', v_id, 'code', v_code);
end $f$;

-- Actions du livreur : accepter | refuser | prise_en_charge | demarrer | confirmer | echec
create or replace function public.livraison_action(p_lid uuid, p_action text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); v_me uuid := app.livreur_id(); l public.livraisons%rowtype; c public.commandes%rowtype;
  v_code text; v_m int; v_ecart int; v_pos record; v_motif text := btrim(coalesce(p->>'motif', ''));
begin
  if v_me is null then perform app.deny(); end if;
  select * into l from public.livraisons where id = p_lid and org_id = v_org and livreur_id = v_me for update;
  if not found then raise exception 'Mission introuvable'; end if;
  select * into c from public.commandes where id = l.commande_id for update;

  if p_action = 'accepter' then
    if l.statut <> 'affectee' then raise exception 'Mission déjà traitée'; end if;
    update public.livraisons set statut = 'acceptee', accept_at = now() where id = p_lid;

  elsif p_action = 'refuser' then
    if l.statut not in ('affectee', 'acceptee') then raise exception 'Mission déjà démarrée'; end if;
    if v_motif = '' then raise exception 'Motif obligatoire'; end if;
    update public.livraisons set statut = 'refusee', fin_at = now(), motif = v_motif where id = p_lid;
    perform app.set_statut(c.id, 'prete', 'Refus du livreur : ' || v_motif);
    perform app.log(v_org, 'Refus de mission', c.numero || ' — ' || v_motif);

  elsif p_action = 'prise_en_charge' then
    if l.statut <> 'acceptee' or l.collecte_at is not null then raise exception 'Prise en charge impossible'; end if;
    if coalesce((p->>'nb_colis')::int, 0) < 1 then raise exception 'Nombre de colis invalide'; end if;
    update public.livraisons set collecte_at = now(), nb_colis = (p->>'nb_colis')::int, etat_colis = left(p->>'etat', 100) where id = p_lid;

  elsif p_action = 'demarrer' then
    if l.statut <> 'acceptee' or l.collecte_at is null then raise exception 'Confirmez d''abord la prise en charge du colis'; end if;
    perform app.set_statut(c.id, 'en_cours', 'Départ du livreur');
    update public.livraisons set statut = 'en_cours', depart_at = now() where id = p_lid;

  elsif p_action = 'confirmer' then
    if l.statut <> 'en_cours' then raise exception 'Cette livraison n''est pas en cours (déjà validée ?)'; end if;
    if l.essais_code >= 5 then raise exception 'Trop d''essais de code : contactez le superviseur'; end if;
    select code into v_code from public.livraison_codes where livraison_id = p_lid;
    if v_code is distinct from btrim(coalesce(p->>'code', '')) then
      update public.livraisons set essais_code = essais_code + 1 where id = p_lid;     -- committé : on ne lève pas d'erreur
      return jsonb_build_object('ok', false, 'erreur', 'Code de confirmation incorrect', 'essais_restants', 4 - l.essais_code);
    end if;
    if l.montant_attendu > 0 and (p->>'montant') is null then raise exception 'Saisissez le montant encaissé (0 si rien reçu)'; end if;
    v_m := coalesce((p->>'montant')::int, 0);
    if v_m < 0 then raise exception 'Montant invalide'; end if;
    v_ecart := v_m - l.montant_attendu;
    if v_ecart <> 0 and btrim(coalesce(p->>'ecart_note', '')) = '' then
      raise exception 'Écart de % F : explication obligatoire', v_ecart;
    end if;
    perform app.set_statut(c.id, 'livree', 'Livrée — reçu par ' || coalesce(p->>'recu_par', ''));
    select lat, lng into v_pos from public.positions_gps where livreur_id = v_me order by ts desc limit 1;
    update public.livraisons set statut = 'livree', fin_at = now(), recu_par = left(p->>'recu_par', 120), obs = left(p->>'obs', 500),
           montant_encaisse = v_m, mode = p->>'mode', ecart = v_ecart,
           ecart_statut = case when v_ecart <> 0 then 'a_valider' end, ecart_note = case when v_ecart <> 0 then left(p->>'ecart_note', 500) end,
           gps_confirm_lat = v_pos.lat, gps_confirm_lng = v_pos.lng
     where id = p_lid;
    if v_m > 0 then
      insert into public.fonds(org_id, type, livreur_id, livraison_id, commande_id, montant, mode, par, par_nom)
      values (v_org, 'encaissement', v_me, p_lid, c.id, v_m, p->>'mode', auth.uid(), (select nom from public.membres where user_id = auth.uid()));
    end if;
    perform app.log(v_org, 'Confirmation livraison', c.numero || ' — encaissé ' || v_m || ' / attendu ' || l.montant_attendu);

  elsif p_action = 'echec' then
    if l.statut not in ('affectee', 'acceptee', 'en_cours') then raise exception 'Livraison déjà clôturée'; end if;
    if v_motif = '' then raise exception 'Motif obligatoire'; end if;
    perform app.set_statut(c.id, 'echouee', 'Échec : ' || v_motif);
    update public.livraisons set statut = 'echouee', fin_at = now(), motif_echec = v_motif, obs = left(p->>'obs', 500) where id = p_lid;
    perform app.log(v_org, 'Livraison échouée', c.numero || ' — ' || v_motif);
  else
    raise exception 'Action inconnue : %', p_action;
  end if;
  return jsonb_build_object('ok', true);
end $f$;

-- Disponibilité et consentement GPS du livreur
create or replace function public.livreur_set_statut(p_statut text) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if app.livreur_id() is null then perform app.deny(); end if;
  if p_statut not in ('disponible', 'indisponible') then raise exception 'Statut invalide'; end if;
  update public.livreurs set statut = p_statut where id = app.livreur_id();
end $f$;

create or replace function public.livreur_consentement() returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if app.livreur_id() is null then perform app.deny(); end if;
  update public.livreurs set gps_consent = true where id = app.livreur_id();
  perform app.log(app.org(), 'Consentement GPS', '');
end $f$;

-- Position GPS : uniquement pendant une course en cours, après consentement
create or replace function public.enregistrer_position(p_lat numeric, p_lng numeric, p_acc int default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_me uuid := app.livreur_id(); v_l uuid;
begin
  if v_me is null then perform app.deny(); end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Coordonnées invalides'; end if;
  if not (select gps_consent from public.livreurs where id = v_me) then raise exception 'Consentement GPS requis'; end if;
  select id into v_l from public.livraisons where livreur_id = v_me and statut = 'en_cours' limit 1;
  if v_l is null then raise exception 'Le suivi GPS n''est autorisé que pendant une course en cours'; end if;
  insert into public.positions_gps(org_id, livreur_id, livraison_id, lat, lng, acc) values (app.org(), v_me, v_l, round(p_lat, 6), round(p_lng, 6), p_acc);
end $f$;

-- Dernières positions (une par livreur)
create or replace function public.dernieres_positions() returns table (livreur_id uuid, livraison_id uuid, lat numeric, lng numeric, acc int, ts timestamptz)
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'superviseur', 'direction') then perform app.deny(); end if;
  return query select distinct on (p.livreur_id) p.livreur_id, p.livraison_id, p.lat, p.lng, p.acc, p.ts
    from public.positions_gps p where p.org_id = app.org() order by p.livreur_id, p.ts desc;
end $f$;

-- Finance : soldes des livreurs
create or replace function public.solde_livreurs() returns table (livreur_id uuid, encaisse bigint, reverse bigint, solde bigint)
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (app.has_role('admin', 'direction', 'caissier', 'superviseur') or app.livreur_id() is not null) then perform app.deny(); end if;
  return query
    select l.id, coalesce(sum(f.montant) filter (where f.type = 'encaissement'), 0)::bigint,
           coalesce(sum(f.montant) filter (where f.type = 'reversement'), 0)::bigint,
           (coalesce(sum(f.montant) filter (where f.type = 'encaissement'), 0)
            - coalesce(sum(f.montant) filter (where f.type = 'reversement'), 0))::bigint
    from public.livreurs l left join public.fonds f on f.livreur_id = l.id
    where l.org_id = app.org() and (app.livreur_id() is null or l.id = app.livreur_id())
    group by l.id;
end $f$;

-- Reversement : jamais sur simple déclaration du livreur
create or replace function public.reversement(p_lid uuid, p_montant int, p_mode text, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_solde bigint;
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  perform 1 from public.livreurs where id = p_lid and org_id = v_org for update;
  if not found then raise exception 'Livreur introuvable'; end if;
  select coalesce(sum(case type when 'encaissement' then montant when 'reversement' then -montant end), 0) into v_solde
    from public.fonds where livreur_id = p_lid;
  if p_montant is null or p_montant <= 0 or p_montant > v_solde then raise exception 'Montant invalide (restant à reverser : % F)', v_solde; end if;
  insert into public.fonds(org_id, type, livreur_id, montant, mode, note, par, par_nom)
  values (v_org, 'reversement', p_lid, p_montant, p_mode, p_note, auth.uid(), (select nom from public.membres where user_id = auth.uid()));
  perform app.log(v_org, 'Reversement validé', (select nom from public.livreurs where id = p_lid) || ' — ' || p_montant || ' F (reste ' || (v_solde - p_montant) || ' F)');
end $f$;

create or replace function public.valider_ecart(p_lid uuid, p_accepte boolean, p_decision text) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); l public.livraisons%rowtype;
begin
  if not app.has_role('admin', 'superviseur', 'direction') then perform app.deny(); end if;
  if coalesce(btrim(p_decision), '') = '' then raise exception 'Décision obligatoire'; end if;
  select * into l from public.livraisons where id = p_lid and org_id = v_org and ecart_statut = 'a_valider' for update;
  if not found then raise exception 'Aucun écart en attente pour cette livraison'; end if;
  update public.livraisons set ecart_statut = case when p_accepte then 'valide' else 'rejete' end, ecart_decision = p_decision, ecart_par = auth.uid() where id = p_lid;
  perform app.log(v_org, case when p_accepte then 'Écart validé' else 'Écart rejeté' end, p_lid::text || ' ' || l.ecart || ' F — ' || p_decision);
end $f$;

-- Ajustement de stock (inventaire) : seule voie d'écriture du stock
create or replace function public.ajuster_stock(p_produit uuid, p_nouveau int, p_motif text) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_old int; v_nom text;
begin
  if not app.has_role('admin', 'commercial', 'preparateur') then perform app.deny(); end if;
  if p_nouveau is null or p_nouveau < 0 then raise exception 'Stock invalide'; end if;
  if coalesce(btrim(p_motif), '') = '' then raise exception 'Justification obligatoire'; end if;
  select stock, nom into v_old, v_nom from public.produits where id = p_produit and org_id = v_org for update;
  if not found then raise exception 'Produit introuvable'; end if;
  if p_nouveau <> v_old then
    perform app.stock_mvt(v_org, p_produit, p_nouveau - v_old, 'ajustement', p_motif);
    perform app.log(v_org, 'Ajustement de stock', v_nom || ' ' || (p_nouveau - v_old) || ' — ' || p_motif);
  end if;
end $f$;

-- Vendeurs partenaires : montant dû (net = articles - commission, commandes livrées et entièrement payées)
create or replace function public.vendeur_dues(p_vid uuid default null) returns table (vendeur_id uuid, acquis bigint, regle bigint, restant bigint, attente bigint)
language plpgsql stable security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_target uuid := p_vid;
begin
  if app.role() = 'vendeur' then v_target := app.vendeur_id();
  elsif not app.has_role('admin', 'direction', 'caissier', 'commercial', 'superviseur') then perform app.deny(); end if;
  return query
    select v.id,
      coalesce(sum(round((c.montant_produits - c.remise) * (1 - v.commission_pct / 100)))
        filter (where c.statut = 'livree' and not c.vendeur_encaisse and app.solde_commande(c.id) = 0), 0)::bigint as a,
      (select coalesce(sum(r.montant), 0) from public.reglements_vendeurs r where r.vendeur_id = v.id)::bigint as g,
      (coalesce(sum(round((c.montant_produits - c.remise) * (1 - v.commission_pct / 100)))
        filter (where c.statut = 'livree' and not c.vendeur_encaisse and app.solde_commande(c.id) = 0), 0)
       - (select coalesce(sum(r.montant), 0) from public.reglements_vendeurs r where r.vendeur_id = v.id))::bigint as rest,
      coalesce(sum(round((c.montant_produits - c.remise) * (1 - v.commission_pct / 100)))
        filter (where c.statut in ('confirmee','preparation','prete','affectee','en_cours') and not c.vendeur_encaisse), 0)::bigint as att
    from public.vendeurs v left join public.commandes c on c.vendeur_id = v.id
    where v.org_id = v_org and (v_target is null or v.id = v_target)
    group by v.id, v.commission_pct;
end $f$;

create or replace function public.regler_vendeur(p_vid uuid, p_montant int, p_mode text, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_rest bigint;
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  perform 1 from public.vendeurs where id = p_vid and org_id = v_org for update;
  if not found then raise exception 'Vendeur introuvable'; end if;
  select restant into v_rest from public.vendeur_dues(p_vid);
  if p_montant is null or p_montant <= 0 or p_montant > v_rest then raise exception 'Montant invalide (reste à régler : % F)', v_rest; end if;
  insert into public.reglements_vendeurs(org_id, vendeur_id, montant, mode, note, par, par_nom)
  values (v_org, p_vid, p_montant, p_mode, p_note, auth.uid(), (select nom from public.membres where user_id = auth.uid()));
  perform app.log(v_org, 'Règlement vendeur', (select nom from public.vendeurs where id = p_vid) || ' — ' || p_montant || ' F');
end $f$;

-- Position d'une adresse posée par le personnel
create or replace function public.appliquer_position_adresse(p_adresse uuid, p_lat numeric, p_lng numeric, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'superviseur', 'commercial') then perform app.deny(); end if;
  perform app.maj_position(app.org(), p_adresse, p_lat, p_lng, 'saisie par le personnel', null, p_note);
  perform app.log(app.org(), 'Position GPS d''une adresse', p_adresse::text);
end $f$;

-- Incident : numérotation côté serveur
create or replace function public.declarer_incident(p_cat text, p_commande uuid, p_descr text) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_n int; v_ref text;
begin
  if v_org is null then perform app.deny(); end if;
  if coalesce(btrim(p_descr), '') = '' then raise exception 'Description obligatoire'; end if;
  insert into public.compteurs(org_id, inc) values (v_org, 1) on conflict (org_id) do update set inc = public.compteurs.inc + 1 returning inc into v_n;
  v_ref := 'INC-' || lpad(v_n::text, 4, '0');
  insert into public.incidents(org_id, ref, cat, commande_id, par_user, par_nom, descr)
  values (v_org, v_ref, p_cat, p_commande, auth.uid(), (select nom from public.membres where user_id = auth.uid()), left(p_descr, 2000));
  perform app.log(v_org, 'Incident déclaré', v_ref || ' — ' || p_cat);
  return v_ref;
end $f$;

-- Portail client : lien personnel pour que le client géolocalise son adresse
create or replace function public.creer_lien_portail(p_adresse uuid, p_ref text default null) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); a public.adresses%rowtype; v_ok boolean := false; v_token text;
begin
  select * into a from public.adresses where id = p_adresse and org_id = v_org;
  if not found then raise exception 'Adresse introuvable'; end if;
  if app.has_role('admin', 'superviseur', 'commercial') then v_ok := true;
  elsif app.role() = 'vendeur' then
    v_ok := exists (select 1 from public.clients c where c.id = a.client_id and c.vendeur_id = app.vendeur_id());
  elsif app.role() = 'livreur' then v_ok := app.livreur_voit_adresse(p_adresse);
  end if;
  if not v_ok then perform app.deny(); end if;
  insert into public.portail_liens(org_id, adresse_id, ref) values (v_org, p_adresse, left(p_ref, 60)) returning token into v_token;
  return v_token;
end $f$;

create or replace function public.portail_get(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare r record;
begin
  select o.nom as org, o.whatsapp, c.nom as client, a.libelle, a.zone, a.quartier, a.repere, a.lat, a.lng, l.ref
    into r from public.portail_liens l join public.adresses a on a.id = l.adresse_id
    join public.clients c on c.id = a.client_id join public.organisations o on o.id = l.org_id
   where l.token = p_token and l.expires_at > now() and l.essais < 10;
  if not found then return null; end if;
  return jsonb_build_object('org', r.org, 'w', r.whatsapp, 'n', r.client, 'r', r.ref,
    'a', concat_ws(' · ', r.libelle, r.zone, r.quartier, r.repere),
    'g', case when r.lat is null then null else jsonb_build_object('lat', r.lat, 'lng', r.lng) end);
end $f$;

create or replace function public.portail_poser(p_token text, p_lat numeric, p_lng numeric, p_acc int default null, p_note text default null) returns boolean
language plpgsql security definer set search_path = '' as $f$
declare l public.portail_liens%rowtype;
begin
  select * into l from public.portail_liens where token = p_token and expires_at > now() and essais < 10 for update;
  if not found then return false; end if;
  perform app.maj_position(l.org_id, l.adresse_id, p_lat, p_lng, 'client', p_acc, p_note);
  update public.portail_liens set essais = essais + 1, used_at = now() where token = p_token;
  perform app.log(l.org_id, 'Position confirmée par le client', l.adresse_id::text);
  return true;
end $f$;

-- Amorçage d'une organisation (à exécuter par le propriétaire du projet, jamais exposé à l'API)
create or replace function public.amorcer_organisation(p_nom text, p_admin_user uuid, p_admin_nom text, p_whatsapp text default null) returns uuid
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := gen_random_uuid();
begin
  insert into public.organisations(id, nom, whatsapp, config) values (v_org, p_nom, p_whatsapp, jsonb_build_object(
    'gps_stale_ok', 2, 'gps_stale_warn', 10, 'gps_interval', 20, 'gps_retention_jours', 30,
    'remu', jsonb_build_object('type', 'mixte', 'fixe', 500, 'pct', 0),
    'modes', jsonb_build_array('Espèces', 'Mobile Money', 'Virement', 'Autre'),
    'motifs', jsonb_build_array('Client absent', 'Client injoignable', 'Adresse incorrecte', 'Accès impossible', 'Client a refusé le colis', 'Paiement indisponible', 'Colis endommagé', 'Incident de moto', 'Conditions de sécurité défavorables', 'Autre motif'),
    'cats', jsonb_build_array('Retard', 'Colis manquant', 'Colis endommagé', 'Mauvaise adresse', 'Erreur de montant', 'Contestation de livraison', 'Panne de moto', 'Incident de sécurité', 'Réclamation client')));
  insert into public.compteurs(org_id) values (v_org);
  insert into public.membres(user_id, org_id, role, nom) values (p_admin_user, v_org, 'admin', p_admin_nom);
  insert into public.zones(org_id, nom, frais, delai_min) values
    (v_org, 'Cocody', 1500, 45), (v_org, 'Abobo', 2000, 60), (v_org, 'Yopougon', 2000, 60), (v_org, 'Marcory', 1500, 40),
    (v_org, 'Treichville', 1500, 40), (v_org, 'Koumassi', 2000, 50), (v_org, 'Port-Bouët', 2500, 60), (v_org, 'Plateau', 1500, 40);
  return v_org;
end $f$;

-- ---------------------------------------------------------------------
-- 5. Sécurité : RLS (lecture) et privilèges
-- ---------------------------------------------------------------------
do $f$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $f$;

-- organisations / membres
create policy org_select on public.organisations for select to authenticated using (id = (select app.org()));
create policy org_update on public.organisations for update to authenticated
  using (id = (select app.org()) and (select app.has_role('admin'))) with check (id = (select app.org()));
create policy membres_select on public.membres for select to authenticated
  using (org_id = (select app.org()) and (user_id = (select auth.uid()) or (select app.has_role('admin', 'direction', 'superviseur'))));
create policy membres_update on public.membres for update to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin'))) with check (org_id = (select app.org()));

-- référentiels
create policy zones_select on public.zones for select to authenticated using (org_id = (select app.org()));
create policy zones_write on public.zones for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin'))) with check (org_id = (select app.org()));

create policy produits_select on public.produits for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur', 'caissier')));
create policy produits_write on public.produits for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'commercial')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'commercial')));

create policy clients_select on public.clients for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur', 'commercial'))
  or (vendeur_id is not null and vendeur_id = (select app.vendeur_id()))
  or app.livreur_voit_client(id)));
create policy clients_write on public.clients for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'commercial')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'commercial')));

create policy adresses_select on public.adresses for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur', 'commercial'))
  or client_id in (select c.id from public.clients c where c.vendeur_id is not null and c.vendeur_id = (select app.vendeur_id()))
  or app.livreur_voit_adresse(id)));
create policy adresses_write on public.adresses for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'commercial')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'commercial')));

create policy livreurs_select on public.livreurs for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur', 'caissier')) or id = (select app.livreur_id())));
create policy livreurs_write on public.livreurs for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')));

create policy motos_select on public.motos for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur')) or id = (select app.livreur_moto())));
create policy motos_write on public.motos for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')));

create policy vendeurs_select on public.vendeurs for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'caissier')) or id = (select app.vendeur_id())));
create policy vendeurs_write on public.vendeurs for all to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'commercial')))
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'commercial')));

-- commandes (lecture seule : toute écriture passe par les RPC)
create policy commandes_select on public.commandes for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur', 'caissier'))
  or (vendeur_id is not null and vendeur_id = (select app.vendeur_id()))
  or app.livreur_voit_commande(id)));
create policy lignes_select on public.commande_lignes for select to authenticated
  using (org_id = (select app.org()) and commande_id in (select c.id from public.commandes c));
create policy histo_select on public.commande_historique for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur')));

create policy livraisons_select on public.livraisons for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur', 'caissier'))
  or livreur_id = (select app.livreur_id())));
create policy codes_select on public.livraison_codes for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'commercial')));
create policy positions_select on public.positions_gps for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'direction')));

-- argent
create policy fonds_select on public.fonds for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'caissier', 'superviseur')) or livreur_id = (select app.livreur_id())));
create policy paie_select on public.paiements_livreurs for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'caissier')) or livreur_id = (select app.livreur_id())));
create policy paie_insert on public.paiements_livreurs for insert to authenticated
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'caissier')));
create policy dep_select on public.depenses for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'caissier')) or livreur_id = (select app.livreur_id())));
create policy dep_insert on public.depenses for insert to authenticated
  with check (org_id = (select app.org()) and (select app.has_role('admin', 'caissier')));
create policy regl_select on public.reglements_vendeurs for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'caissier')) or vendeur_id = (select app.vendeur_id())));

-- incidents, retours, stock, audit
create policy inc_select on public.incidents for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur', 'preparateur')) or par_user = (select auth.uid())));
create policy inc_update on public.incidents for update to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur')))
  with check (org_id = (select app.org()));
create policy retours_select on public.retours for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'superviseur', 'preparateur')));
create policy stockm_select on public.stock_mouvements for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur')));
create policy audit_select on public.audit_log for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction')));
-- compteurs, portail_liens : RLS activée sans politique = inaccessibles en direct.

-- Privilèges : on repart de zéro, puis on n'accorde que le nécessaire
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

grant select on public.organisations, public.membres, public.zones, public.produits, public.clients, public.adresses,
  public.livreurs, public.motos, public.vendeurs, public.commandes, public.commande_lignes, public.commande_historique,
  public.livraisons, public.livraison_codes, public.positions_gps, public.fonds, public.paiements_livreurs, public.depenses,
  public.reglements_vendeurs, public.incidents, public.retours, public.stock_mouvements, public.audit_log to authenticated;

-- Écritures directes autorisées (les politiques RLS filtrent par profil). Le stock n'est jamais modifiable en direct.
grant update (nom, whatsapp, config) on public.organisations to authenticated;
grant update (actif, nom, role) on public.membres to authenticated;
grant insert, update, delete on public.zones, public.clients, public.adresses, public.livreurs, public.motos, public.vendeurs to authenticated;
grant insert (org_id, code, nom, prix, seuil, actif), update (code, nom, prix, seuil, actif), delete on public.produits to authenticated;
grant insert on public.paiements_livreurs, public.depenses to authenticated;
grant update (statut, decision, responsable) on public.incidents to authenticated;

-- Fonctions : aucune par défaut ; RPC pour les utilisateurs connectés ; portail pour le public
grant usage on schema app to authenticated;
do $f$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('app', 'public') and p.prokind = 'f' loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $f$;
grant execute on all functions in schema app to authenticated;
grant execute on function
  public.creer_commande(jsonb), public.vendeur_deposer_commande(jsonb), public.commande_action(uuid, text, text),
  public.corriger_statut(uuid, text, text), public.reception_retour(uuid, jsonb, text, text, text),
  public.affecter_livraison(uuid, uuid, text, boolean), public.livraison_action(uuid, text, jsonb),
  public.livreur_set_statut(text), public.livreur_consentement(), public.enregistrer_position(numeric, numeric, int),
  public.dernieres_positions(), public.solde_livreurs(), public.reversement(uuid, int, text, text),
  public.valider_ecart(uuid, boolean, text), public.ajuster_stock(uuid, int, text), public.vendeur_dues(uuid),
  public.regler_vendeur(uuid, int, text, text), public.appliquer_position_adresse(uuid, numeric, numeric, text),
  public.declarer_incident(text, uuid, text), public.creer_lien_portail(uuid, text)
  to authenticated;
grant execute on function public.portail_get(text), public.portail_poser(text, numeric, numeric, int, text) to anon, authenticated;
-- public.amorcer_organisation : réservée au propriétaire (aucun grant)
