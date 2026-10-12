-- Collecte des colis chez le vendeur partenaire après confirmation de ses commandes.
-- Un livreur est missionné ; le vendeur lui remet les colis contre un code à 4 chiffres (qu'il voit dans son espace, pas le livreur) ;
-- à l'arrivée au dépôt, le préparateur réceptionne la collecte : les commandes complètes passent en préparation.

alter table public.vendeurs add column adresse_collecte jsonb;      -- {zone, quartier, repere, lat, lng}

create table public.collectes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  numero text not null,
  vendeur_id uuid not null references public.vendeurs(id),
  vendeur_nom text,                      -- photos instantanées : le livreur ne lit pas la table des vendeurs
  vendeur_tel text,
  livreur_id uuid references public.livreurs(id),
  livreur_prenom text,
  statut text not null default 'planifiee' check (statut in ('planifiee', 'acceptee', 'en_route', 'collectee', 'recue', 'echouee', 'annulee')),
  creneau timestamptz,
  note text,
  adresse jsonb not null,
  essais_code int not null default 0,
  motif text,
  cree_le timestamptz not null default now(),
  cree_par_nom text,
  accept_at timestamptz, depart_at timestamptz, collecte_at timestamptz, recue_at timestamptz, recue_par_nom text,
  unique (org_id, numero)
);
create index on public.collectes (org_id, statut);
create table public.collecte_codes (
  collecte_id uuid primary key references public.collectes(id) on delete cascade,
  org_id uuid not null references public.organisations(id) on delete cascade,
  code text not null
);
create table public.collecte_commandes (
  collecte_id uuid not null references public.collectes(id) on delete cascade,
  commande_id uuid not null references public.commandes(id),
  org_id uuid not null references public.organisations(id) on delete cascade,
  numero text,
  resume text,
  colis_collectes int check (colis_collectes is null or colis_collectes >= 0),
  colis_recus int check (colis_recus is null or colis_recus >= 0),
  primary key (collecte_id, commande_id)
);
create index on public.collecte_commandes (commande_id);

alter table public.collectes enable row level security;
alter table public.collecte_codes enable row level security;
alter table public.collecte_commandes enable row level security;
create policy collectes_select on public.collectes for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur', 'commercial', 'preparateur', 'direction'))
  or (vendeur_id = (select app.vendeur_id())) or (livreur_id is not null and livreur_id = (select app.livreur_id()))));
create policy collecte_cmd_select on public.collecte_commandes for select to authenticated using (org_id = (select app.org()) and exists (
  select 1 from public.collectes c where c.id = collecte_id and (
    (select app.has_role('admin', 'superviseur', 'commercial', 'preparateur', 'direction'))
    or c.vendeur_id = (select app.vendeur_id()) or (c.livreur_id is not null and c.livreur_id = (select app.livreur_id())))));
create policy collecte_codes_select on public.collecte_codes for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur'))
  or exists (select 1 from public.collectes c where c.id = collecte_id and c.vendeur_id is not null and c.vendeur_id = (select app.vendeur_id()))));
grant select on public.collectes, public.collecte_codes, public.collecte_commandes to authenticated;

create or replace function public.maj_adresse_collecte(p jsonb, p_vendeur uuid default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_id uuid;
begin
  if app.role() = 'vendeur' then v_id := app.vendeur_id();
  elsif app.has_role('admin', 'superviseur', 'commercial') then v_id := p_vendeur;
  else perform app.deny(); end if;
  if v_id is null or not exists (select 1 from public.vendeurs where id = v_id and org_id = v_org) then raise exception 'Vendeur introuvable'; end if;
  if coalesce(btrim(p->>'zone'), '') = '' or (coalesce(btrim(p->>'quartier'), '') = '' and coalesce(btrim(p->>'repere'), '') = '') then raise exception 'Indiquez la zone et le quartier ou un point de repère'; end if;
  update public.vendeurs set adresse_collecte = jsonb_build_object('zone', left(btrim(p->>'zone'), 60), 'quartier', left(coalesce(btrim(p->>'quartier'), ''), 80),
    'repere', left(coalesce(btrim(p->>'repere'), ''), 120), 'lat', p->'lat', 'lng', p->'lng') where id = v_id;
  perform app.log(v_org, 'Adresse de collecte mise à jour', (select nom from public.vendeurs where id = v_id));
end $f$;

create or replace function public.planifier_collecte(p_vendeur uuid, p_commandes uuid[], p_livreur uuid, p_creneau timestamptz, p_note text default null, p_adresse jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_id uuid := gen_random_uuid(); v_cle text; v_n int; v_num text; v_adr jsonb; r record;
begin
  if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
  if not exists (select 1 from public.vendeurs where id = p_vendeur and org_id = v_org) then raise exception 'Vendeur introuvable'; end if;
  if not exists (select 1 from public.livreurs where id = p_livreur and org_id = v_org) then raise exception 'Livreur introuvable'; end if;
  if coalesce((select (config ->> 'dossier_obligatoire')::boolean from public.organisations where id = v_org), false) and not app.dossier_complet(p_livreur) then
    raise exception 'Dossier du livreur incomplet ou expiré : mission impossible'; end if;
  if p_commandes is null or cardinality(p_commandes) = 0 then raise exception 'Sélectionnez au moins une commande'; end if;
  for r in select c.id, c.numero, c.statut, c.vendeur_id from public.commandes c where c.id = any (p_commandes) and c.org_id = v_org for update loop
    if r.vendeur_id is distinct from p_vendeur then raise exception 'La commande % n''appartient pas à ce vendeur', r.numero; end if;
    if r.statut <> 'confirmee' then raise exception 'Commande % : elle doit être « confirmée » pour être collectée', r.numero; end if;
    if exists (select 1 from public.collecte_commandes cc join public.collectes c2 on c2.id = cc.collecte_id where cc.commande_id = r.id and c2.statut in ('planifiee', 'acceptee', 'en_route', 'collectee')) then
      raise exception 'Commande % : une collecte est déjà en cours', r.numero; end if;
  end loop;
  if (select count(*) from public.commandes where id = any (p_commandes) and org_id = v_org) <> cardinality(p_commandes) then raise exception 'Commande introuvable'; end if;
  if p_adresse is not null then perform public.maj_adresse_collecte(p_adresse, p_vendeur); end if;
  select adresse_collecte into v_adr from public.vendeurs where id = p_vendeur;
  if v_adr is null then raise exception 'Adresse de collecte du vendeur non renseignée'; end if;
  v_cle := 'COL-' || extract(year from now())::int;
  insert into public.compteurs_docs(org_id, cle, n) values (v_org, v_cle, 1) on conflict (org_id, cle) do update set n = public.compteurs_docs.n + 1 returning n into v_n;
  v_num := v_cle || '-' || lpad(v_n::text, 4, '0');
  insert into public.collectes(id, org_id, numero, vendeur_id, vendeur_nom, vendeur_tel, livreur_id, livreur_prenom, creneau, note, adresse, cree_par_nom)
    select v_id, v_org, v_num, p_vendeur, v.nom, v.tel, p_livreur, split_part((select nom from public.livreurs where id = p_livreur), ' ', 1), p_creneau, left(p_note, 300), v_adr, (select nom from public.membres where user_id = auth.uid())
      from public.vendeurs v where v.id = p_vendeur;
  insert into public.collecte_codes(collecte_id, org_id, code) values (v_id, v_org, lpad((floor(random() * 10000))::int::text, 4, '0'));
  insert into public.collecte_commandes(collecte_id, commande_id, org_id, numero, resume)
    select v_id, c.id, v_org, c.numero, (select string_agg(l.qte || '× ' || coalesce(l.desig, 'Article'), ', ' order by l.id) from public.commande_lignes l where l.commande_id = c.id)
      from public.commandes c where c.id = any (p_commandes);
  perform app.log(v_org, 'Collecte planifiée', v_num || ' — ' || (select nom from public.vendeurs where id = p_vendeur) || ' (' || cardinality(p_commandes) || ' commande(s))');
  return jsonb_build_object('id', v_id, 'numero', v_num);
end $f$;

create or replace function public.collecte_action(p_collecte uuid, p_action text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.collectes%rowtype; v_code text; v_nom text := (select nom from public.membres where user_id = auth.uid());
        r record; v_n int; v_tot int := 0; v_liv uuid;
begin
  select * into c from public.collectes where id = p_collecte and org_id = v_org for update;
  if not found then raise exception 'Collecte introuvable'; end if;
  if p_action in ('accepter', 'refuser', 'partir', 'collecter', 'echec') then
    if app.role() <> 'livreur' or c.livreur_id is distinct from app.livreur_id() then perform app.deny(); end if;
  end if;
  if p_action = 'accepter' then
    if c.statut <> 'planifiee' then raise exception 'Cette collecte ne peut plus être acceptée'; end if;
    update public.collectes set statut = 'acceptee', accept_at = now() where id = c.id;
  elsif p_action = 'refuser' or p_action = 'echec' then
    if c.statut not in ('planifiee', 'acceptee', 'en_route') then raise exception 'Collecte déjà terminée'; end if;
    if coalesce(btrim(p->>'motif'), '') = '' then raise exception 'Motif obligatoire'; end if;
    update public.collectes set statut = 'echouee', motif = left(btrim(p->>'motif'), 300) where id = c.id;
    perform app.log(v_org, 'Collecte non réalisée', c.numero || ' — ' || left(btrim(p->>'motif'), 100));
  elsif p_action = 'partir' then
    if c.statut <> 'acceptee' then raise exception 'Acceptez d''abord la collecte'; end if;
    update public.collectes set statut = 'en_route', depart_at = now() where id = c.id;
  elsif p_action = 'collecter' then
    if c.statut not in ('acceptee', 'en_route') then raise exception 'Cette collecte n''est pas en cours'; end if;
    if c.essais_code >= 5 then raise exception 'Trop d''essais de code : contactez le superviseur'; end if;
    select code into v_code from public.collecte_codes where collecte_id = c.id;
    if v_code is distinct from btrim(coalesce(p->>'code', '')) then
      update public.collectes set essais_code = essais_code + 1 where id = c.id;
      return jsonb_build_object('ok', false, 'erreur', 'Code du vendeur incorrect', 'essais_restants', 4 - c.essais_code);
    end if;
    for r in select commande_id from public.collecte_commandes where collecte_id = c.id loop
      v_n := coalesce((p -> 'colis' ->> r.commande_id::text)::int, 0);
      if v_n < 0 then raise exception 'Nombre de colis invalide'; end if;
      update public.collecte_commandes set colis_collectes = v_n where collecte_id = c.id and commande_id = r.commande_id;
      v_tot := v_tot + v_n;
    end loop;
    if v_tot = 0 then raise exception 'Indiquez le nombre de colis pris pour au moins une commande'; end if;
    update public.collectes set statut = 'collectee', collecte_at = now() where id = c.id;
    perform app.log(v_org, 'Colis collectés', c.numero || ' — ' || v_tot || ' colis');
  elsif p_action = 'recevoir' then
    if not app.has_role('admin', 'preparateur') then perform app.deny(); end if;
    if c.statut <> 'collectee' then raise exception 'Cette collecte n''est pas arrivée au dépôt'; end if;
    for r in select cc.commande_id, cc.colis_collectes, co.statut as cstat from public.collecte_commandes cc join public.commandes co on co.id = cc.commande_id where cc.collecte_id = c.id loop
      v_n := coalesce((p -> 'recus' ->> r.commande_id::text)::int, r.colis_collectes, 0);
      if v_n < 0 then raise exception 'Nombre de colis invalide'; end if;
      update public.collecte_commandes set colis_recus = v_n where collecte_id = c.id and commande_id = r.commande_id;
      if coalesce(r.colis_collectes, 0) > 0 and v_n >= r.colis_collectes and r.cstat = 'confirmee' then
        perform public.commande_action(r.commande_id, 'preparer');
      end if;
    end loop;
    update public.collectes set statut = 'recue', recue_at = now(), recue_par_nom = v_nom where id = c.id;
    perform app.log(v_org, 'Collecte réceptionnée', c.numero);
  elsif p_action = 'reaffecter' then
    if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
    if c.statut not in ('planifiee', 'acceptee', 'echouee') then raise exception 'Cette collecte ne peut plus être réaffectée'; end if;
    v_liv := (p->>'livreur')::uuid;
    if not exists (select 1 from public.livreurs where id = v_liv and org_id = v_org) then raise exception 'Livreur introuvable'; end if;
    if coalesce((select (config ->> 'dossier_obligatoire')::boolean from public.organisations where id = v_org), false) and not app.dossier_complet(v_liv) then
      raise exception 'Dossier du livreur incomplet ou expiré : mission impossible'; end if;
    update public.collectes set livreur_id = v_liv, livreur_prenom = split_part((select nom from public.livreurs where id = v_liv), ' ', 1), statut = 'planifiee', motif = null, accept_at = null, creneau = coalesce((p->>'creneau')::timestamptz, creneau), essais_code = 0 where id = c.id;
    perform app.log(v_org, 'Collecte réaffectée', c.numero);
  elsif p_action = 'annuler' then
    if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
    if c.statut in ('recue', 'annulee') then raise exception 'Collecte déjà clôturée'; end if;
    if coalesce(btrim(p->>'motif'), '') = '' then raise exception 'Motif obligatoire'; end if;
    update public.collectes set statut = 'annulee', motif = left(btrim(p->>'motif'), 300) where id = c.id;
    perform app.log(v_org, 'Collecte annulée', c.numero || ' — ' || left(btrim(p->>'motif'), 100));
  else raise exception 'Action inconnue'; end if;
  return jsonb_build_object('ok', true);
end $f$;

revoke all on function public.maj_adresse_collecte(jsonb, uuid), public.planifier_collecte(uuid, uuid[], uuid, timestamptz, text, jsonb), public.collecte_action(uuid, text, jsonb) from public, anon;
grant execute on function public.maj_adresse_collecte(jsonb, uuid), public.planifier_collecte(uuid, uuid[], uuid, timestamptz, text, jsonb), public.collecte_action(uuid, text, jsonb) to authenticated;
