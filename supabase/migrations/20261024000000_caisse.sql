-- Module Caisse (espèces d'ANGEL'S GROUP) : caisses, sessions d'ouverture/clôture, bons d'entrée et de sortie numérotés,
-- validation hiérarchique, écarts de clôture à régulariser, intégration automatique des flux en espèces.
-- Règles (inspirées d'ImmoSuite) : toute écriture passe par une fonction ; rien ne se supprime (un bon se rejette ou se contre-passe) ;
-- un bon saisi par un caissier ne compte dans le solde qu'une fois validé par l'administrateur ou la direction ;
-- on ne clôture pas avec des bons en attente ; un écart de clôture exige une justification puis une régularisation.

create table public.caisses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  nom text not null check (char_length(btrim(nom)) between 1 and 60),
  compte text not null default '571' check (compte in ('571', '572')),   -- 571 caisse principale, 572 petite caisse / caisse annexe
  actif boolean not null default true,
  cree_le timestamptz not null default now(),
  unique (org_id, nom)
);

create table public.caisse_sessions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  caisse_id uuid not null references public.caisses(id) on delete cascade,
  statut text not null default 'ouverte' check (statut in ('ouverte', 'cloturee')),
  fond_ouverture int not null check (fond_ouverture >= 0),
  fond_attendu int,                       -- fond réel compté à la clôture précédente (continuité de la caisse)
  ouverte_par_nom text,
  ouverte_le timestamptz not null default now(),
  note_ouverture text,
  fond_cloture_theorique int,
  fond_cloture_reel int check (fond_cloture_reel >= 0),
  ecart int,                              -- réel - théorique (négatif = manquant)
  justification text,
  cloturee_par_nom text,
  cloturee_le timestamptz,
  ecart_regularise boolean not null default false,
  regularise_par_nom text,
  regularise_le timestamptz,
  regularise_note text
);
create unique index caisse_une_session_ouverte on public.caisse_sessions (caisse_id) where statut = 'ouverte';
create index on public.caisse_sessions (org_id, caisse_id, ouverte_le desc);

create table public.caisse_mouvements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  caisse_id uuid not null references public.caisses(id) on delete cascade,
  session_id uuid not null references public.caisse_sessions(id) on delete cascade,
  numero text not null,
  type text not null check (type in ('entree', 'sortie')),
  montant int not null check (montant > 0),
  motif text not null check (char_length(btrim(motif)) between 1 and 200),
  tiers text check (char_length(tiers) <= 120),            -- déposant (entrée) ou bénéficiaire (sortie)
  piece_ref text check (char_length(piece_ref) <= 80),
  categorie text check (char_length(categorie) <= 60),
  statut text not null default 'en_attente' check (statut in ('en_attente', 'valide', 'rejete')),
  source text not null default 'manuel' check (source in ('manuel', 'reversement', 'reglement_vendeur', 'paie')),
  source_id uuid,
  cree_par_nom text,
  cree_le timestamptz not null default now(),
  valide_par_nom text,
  valide_le timestamptz,
  motif_rejet text,
  unique (org_id, numero)
);
create index on public.caisse_mouvements (org_id, caisse_id, cree_le desc);
create index on public.caisse_mouvements (session_id);
create unique index caisse_source_unique on public.caisse_mouvements (source, source_id) where source_id is not null;

alter table public.caisses enable row level security;
alter table public.caisse_sessions enable row level security;
alter table public.caisse_mouvements enable row level security;
create policy caisses_select on public.caisses for select to authenticated using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'caissier')));
create policy caisse_sessions_select on public.caisse_sessions for select to authenticated using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'caissier')));
create policy caisse_mvts_select on public.caisse_mouvements for select to authenticated using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'caissier')));
grant select on public.caisses, public.caisse_sessions, public.caisse_mouvements to authenticated;   -- aucune écriture directe : uniquement les fonctions ci-dessous

-- Solde d'une session : fond + entrées validées - sorties validées (un bon en attente ou rejeté ne compte jamais)
create or replace function app.caisse_solde_session(p_session uuid) returns bigint
language sql stable security definer set search_path = '' as $f$
  select (s.fond_ouverture + coalesce(sum(case when m.type = 'entree' then m.montant else -m.montant end) filter (where m.statut = 'valide'), 0))::bigint
  from public.caisse_sessions s left join public.caisse_mouvements m on m.session_id = s.id
  where s.id = p_session group by s.id
$f$;

-- Numéro de bon : BE|BS-<compte>-AAAAMMJJ-NNN, séquentiel par jour, caisse et nature
create or replace function app.caisse_numero(p_org uuid, p_caisse uuid, p_type text) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_compte text; v_pre text; v_n int;
begin
  select compte into v_compte from public.caisses where id = p_caisse;
  v_pre := (case when p_type = 'entree' then 'BE' else 'BS' end) || '-' || v_compte || '-' || to_char(now() at time zone 'Africa/Abidjan', 'YYYYMMDD') || '-';
  perform pg_advisory_xact_lock(hashtext(p_org::text || v_pre));
  select coalesce(max(substring(numero from '[0-9]+$')::int), 0) + 1 into v_n from public.caisse_mouvements where org_id = p_org and numero like v_pre || '%';
  return v_pre || lpad(v_n::text, 3, '0');
end $f$;

create or replace function app.caisse_inserer(p_org uuid, p_caisse uuid, p_session uuid, p_type text, p_montant int, p_motif text, p_tiers text,
  p_piece text, p_cat text, p_statut text, p_source text, p_source_id uuid, p_par text) returns public.caisse_mouvements
language plpgsql security definer set search_path = '' as $f$
declare r public.caisse_mouvements;
begin
  insert into public.caisse_mouvements(org_id, caisse_id, session_id, numero, type, montant, motif, tiers, piece_ref, categorie, statut, source, source_id,
      cree_par_nom, valide_par_nom, valide_le)
    values (p_org, p_caisse, p_session, app.caisse_numero(p_org, p_caisse, p_type), p_type, p_montant, btrim(p_motif), nullif(btrim(coalesce(p_tiers, '')), ''),
      nullif(btrim(coalesce(p_piece, '')), ''), nullif(btrim(coalesce(p_cat, '')), ''), p_statut, p_source, p_source_id, p_par,
      case when p_statut = 'valide' then p_par end, case when p_statut = 'valide' then now() end)
    returning * into r;
  return r;
end $f$;

create or replace function public.caisse_creer(p_nom text, p_compte text default '571') returns uuid
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_id uuid;
begin
  if not app.has_role('admin') then perform app.deny(); end if;
  if coalesce(btrim(p_nom), '') = '' then raise exception 'Nom de la caisse obligatoire'; end if;
  if p_compte not in ('571', '572') then raise exception 'Compte invalide'; end if;
  insert into public.caisses(org_id, nom, compte) values (v_org, btrim(p_nom), p_compte) returning id into v_id;
  perform app.log(v_org, 'Caisse créée', btrim(p_nom));
  return v_id;
end $f$;

create or replace function public.caisse_ouvrir(p_caisse uuid, p_fond int default null, p_note text default null) returns uuid
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.caisses%rowtype; v_last int; v_fond int; v_id uuid; v_nom text := (select nom from public.membres where user_id = auth.uid());
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  select * into c from public.caisses where id = p_caisse and org_id = v_org for update;
  if not found or not c.actif then raise exception 'Caisse introuvable ou inactive'; end if;
  if exists (select 1 from public.caisse_sessions where caisse_id = p_caisse and statut = 'ouverte') then raise exception 'Cette caisse est déjà ouverte'; end if;
  select fond_cloture_reel into v_last from public.caisse_sessions where caisse_id = p_caisse and statut = 'cloturee' order by ouverte_le desc limit 1;
  v_fond := coalesce(p_fond, v_last, 0);
  if v_fond < 0 then raise exception 'Fond de caisse invalide'; end if;
  if v_last is not null and v_fond <> v_last then
    if not app.has_role('admin') then raise exception 'Le fond d''ouverture doit être égal au fond compté à la dernière clôture (% F) : seul l''administrateur peut le modifier', v_last; end if;
    if coalesce(btrim(p_note), '') = '' then raise exception 'Motif obligatoire pour modifier le fond d''ouverture (fond compté à la clôture précédente : % F)', v_last; end if;
  end if;
  insert into public.caisse_sessions(org_id, caisse_id, fond_ouverture, fond_attendu, ouverte_par_nom, note_ouverture)
    values (v_org, p_caisse, v_fond, v_last, v_nom, left(p_note, 200)) returning id into v_id;
  perform app.log(v_org, 'Caisse ouverte', c.nom || ' — fond ' || v_fond || ' F');
  return v_id;
end $f$;

-- Bon d'entrée ou de sortie. Saisi par un caissier : en attente de validation. Saisi par l'administrateur : validé d'office.
create or replace function public.caisse_mouvement(p_caisse uuid, p_type text, p_montant int, p_motif text, p_tiers text default null,
  p_piece text default null, p_categorie text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); s public.caisse_sessions%rowtype; r public.caisse_mouvements; v_nom text := (select nom from public.membres where user_id = auth.uid());
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  if p_type not in ('entree', 'sortie') then raise exception 'Nature du bon invalide'; end if;
  if p_montant is null or p_montant <= 0 then raise exception 'Montant invalide'; end if;
  if coalesce(btrim(p_motif), '') = '' then raise exception 'Motif obligatoire'; end if;
  if coalesce(btrim(p_tiers), '') = '' then raise exception '% obligatoire', case when p_type = 'entree' then 'Déposant' else 'Bénéficiaire' end; end if;
  select * into s from public.caisse_sessions where caisse_id = p_caisse and org_id = v_org and statut = 'ouverte';
  if not found then raise exception 'Ouvrez la caisse avant d''enregistrer un bon'; end if;
  r := app.caisse_inserer(v_org, p_caisse, s.id, p_type, p_montant, p_motif, p_tiers, p_piece, p_categorie,
         case when app.has_role('admin') then 'valide' else 'en_attente' end, 'manuel', null, v_nom);
  perform app.log(v_org, 'Bon de caisse ' || r.numero, p_montant || ' F — ' || left(p_motif, 80));
  return jsonb_build_object('id', r.id, 'numero', r.numero, 'statut', r.statut);
end $f$;

create or replace function public.caisse_valider(p_id uuid, p_decision text, p_motif text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); m public.caisse_mouvements%rowtype; s public.caisse_sessions%rowtype; v_solde bigint; v_nom text := (select nom from public.membres where user_id = auth.uid());
begin
  if not app.has_role('admin', 'direction') then perform app.deny(); end if;
  select * into m from public.caisse_mouvements where id = p_id and org_id = v_org for update;
  if not found then raise exception 'Bon introuvable'; end if;
  if m.statut <> 'en_attente' then raise exception 'Bon déjà traité'; end if;
  select * into s from public.caisse_sessions where id = m.session_id;
  if s.statut <> 'ouverte' then raise exception 'Session clôturée : ce bon ne peut plus être traité'; end if;
  if p_decision = 'valider' then
    if m.type = 'sortie' then
      v_solde := app.caisse_solde_session(s.id);
      if m.montant > v_solde then raise exception 'Solde de caisse insuffisant (% F disponibles)', v_solde; end if;
    end if;
    update public.caisse_mouvements set statut = 'valide', valide_par_nom = v_nom, valide_le = now() where id = p_id;
    perform app.log(v_org, 'Bon de caisse validé', m.numero || ' — ' || m.montant || ' F');
  elsif p_decision = 'rejeter' then
    if coalesce(btrim(p_motif), '') = '' then raise exception 'Motif du rejet obligatoire'; end if;
    update public.caisse_mouvements set statut = 'rejete', valide_par_nom = v_nom, valide_le = now(), motif_rejet = left(btrim(p_motif), 300) where id = p_id;
    perform app.log(v_org, 'Bon de caisse rejeté', m.numero || ' — ' || left(btrim(p_motif), 100));
  else raise exception 'Décision inconnue'; end if;
end $f$;

create or replace function public.caisse_cloturer(p_session uuid, p_reel int, p_justification text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); s public.caisse_sessions%rowtype; v_theo bigint; v_ecart int; v_att int; v_nom text := (select nom from public.membres where user_id = auth.uid());
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  select * into s from public.caisse_sessions where id = p_session and org_id = v_org for update;
  if not found or s.statut <> 'ouverte' then raise exception 'Session introuvable ou déjà clôturée'; end if;
  if p_reel is null or p_reel < 0 then raise exception 'Comptage réel invalide'; end if;
  select count(*) into v_att from public.caisse_mouvements where session_id = p_session and statut = 'en_attente';
  if v_att > 0 then raise exception '% bon(s) en attente de validation : faites-les valider ou rejeter avant la clôture', v_att; end if;
  v_theo := app.caisse_solde_session(p_session);
  v_ecart := p_reel - v_theo;
  if v_ecart <> 0 and length(btrim(coalesce(p_justification, ''))) < 5 then raise exception 'Écart de % F : une justification est obligatoire', v_ecart; end if;
  update public.caisse_sessions set statut = 'cloturee', fond_cloture_theorique = v_theo, fond_cloture_reel = p_reel, ecart = v_ecart,
    justification = nullif(left(btrim(coalesce(p_justification, '')), 300), ''), cloturee_par_nom = v_nom, cloturee_le = now(),
    ecart_regularise = (v_ecart = 0) where id = p_session;
  perform app.log(v_org, 'Caisse clôturée', 'théorique ' || v_theo || ' F, compté ' || p_reel || ' F, écart ' || v_ecart || ' F');
  return jsonb_build_object('theorique', v_theo, 'reel', p_reel, 'ecart', v_ecart);
end $f$;

create or replace function public.caisse_regulariser(p_session uuid, p_note text) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); s public.caisse_sessions%rowtype; v_nom text := (select nom from public.membres where user_id = auth.uid());
begin
  if not app.has_role('admin', 'direction') then perform app.deny(); end if;
  select * into s from public.caisse_sessions where id = p_session and org_id = v_org for update;
  if not found or s.statut <> 'cloturee' or s.ecart is null or s.ecart = 0 or s.ecart_regularise then raise exception 'Aucun écart à régulariser sur cette session'; end if;
  if length(btrim(coalesce(p_note, ''))) < 5 then raise exception 'Précisez la décision (ex. manquant imputé au caissier, erreur de saisie corrigée)'; end if;
  update public.caisse_sessions set ecart_regularise = true, regularise_par_nom = v_nom, regularise_le = now(), regularise_note = left(btrim(p_note), 300) where id = p_session;
  perform app.log(v_org, 'Écart de caisse régularisé', s.ecart || ' F — ' || left(btrim(p_note), 100));
end $f$;

-- Flux en espèces enregistrés automatiquement dans la caisse principale ouverte (validés d'office : ils proviennent d'une opération déjà contrôlée)
create or replace function app.caisse_auto(p_org uuid, p_type text, p_montant int, p_motif text, p_tiers text, p_cat text, p_source text, p_source_id uuid, p_par text) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_caisse uuid; v_session uuid;
begin
  select c.id, s.id into v_caisse, v_session from public.caisses c join public.caisse_sessions s on s.caisse_id = c.id and s.statut = 'ouverte'
   where c.org_id = p_org and c.actif order by c.compte, c.cree_le limit 1;
  if v_session is null then return; end if;
  perform app.caisse_inserer(p_org, v_caisse, v_session, p_type, p_montant, p_motif, p_tiers, null, p_cat, 'valide', p_source, p_source_id, coalesce(p_par, 'Automatique'));
exception when unique_violation then null;
end $f$;

create or replace function app.trg_caisse_reversement() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  if new.type = 'reversement' and new.mode ~* '^esp' then
    perform app.caisse_auto(new.org_id, 'entree', new.montant, 'Reversement livreur ' || coalesce((select nom from public.livreurs where id = new.livreur_id), ''),
      (select nom from public.livreurs where id = new.livreur_id), 'Reversement livreur', 'reversement', new.id, new.par_nom);
  end if;
  return new;
end $f$;
create trigger fonds_caisse after insert on public.fonds for each row execute function app.trg_caisse_reversement();

create or replace function app.trg_caisse_reglement() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  if new.mode ~* '^esp' then
    perform app.caisse_auto(new.org_id, 'sortie', new.montant, 'Règlement vendeur ' || coalesce((select nom from public.vendeurs where id = new.vendeur_id), ''),
      (select nom from public.vendeurs where id = new.vendeur_id), 'Règlement vendeur', 'reglement_vendeur', new.id, new.par_nom);
  end if;
  return new;
end $f$;
create trigger reglements_caisse after insert on public.reglements_vendeurs for each row execute function app.trg_caisse_reglement();

create or replace function app.trg_caisse_paie() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  perform app.caisse_auto(new.org_id, 'sortie', new.montant, (case when new.type = 'avance' then 'Avance au livreur ' else 'Commission livreur ' end) || coalesce((select nom from public.livreurs where id = new.livreur_id), ''),
    (select nom from public.livreurs where id = new.livreur_id), 'Paie livreurs', 'paie', new.id, (select nom from public.membres where user_id = new.par));
  return new;
end $f$;
create trigger paie_caisse after insert on public.paiements_livreurs for each row execute function app.trg_caisse_paie();

revoke all on function app.caisse_solde_session(uuid), app.caisse_numero(uuid, uuid, text), app.caisse_auto(uuid, text, int, text, text, text, text, uuid, text),
  app.trg_caisse_reversement(), app.trg_caisse_reglement(), app.trg_caisse_paie() from public, anon, authenticated;
revoke all on function app.caisse_inserer(uuid, uuid, uuid, text, int, text, text, text, text, text, text, uuid, text) from public, anon, authenticated;
revoke all on function public.caisse_creer(text, text), public.caisse_ouvrir(uuid, int, text), public.caisse_mouvement(uuid, text, int, text, text, text, text),
  public.caisse_valider(uuid, text, text), public.caisse_cloturer(uuid, int, text), public.caisse_regulariser(uuid, text) from public, anon;
grant execute on function public.caisse_creer(text, text), public.caisse_ouvrir(uuid, int, text), public.caisse_mouvement(uuid, text, int, text, text, text, text),
  public.caisse_valider(uuid, text, text), public.caisse_cloturer(uuid, int, text), public.caisse_regulariser(uuid, text) to authenticated;
