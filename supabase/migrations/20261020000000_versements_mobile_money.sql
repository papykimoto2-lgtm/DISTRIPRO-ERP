-- Versements d'argent des livreurs à ANGEL'S GROUP : au comptant (espèces) ou par Mobile Money.
-- Paiement du client à la réception : espèces ou Mobile Money (référence obligatoire) ; en Mobile Money « direct » (sur le compte d'ANGEL'S GROUP)
-- le livreur ne détient rien. Le livreur peut déclarer un virement Mobile Money, le caissier le valide ; le comptant est enregistré par le caissier.

alter table public.fonds add column ref text, add column direct boolean not null default false;
create unique index fonds_ref_unique on public.fonds (org_id, upper(btrim(ref))) where ref is not null;

create or replace function app.est_mobile(p_mode text) returns boolean
language sql immutable set search_path = '' as $f$
  select coalesce(p_mode, '') ~* '(wave|orange|mtn|moov|momo|mobile)'
$f$;

create or replace function public.livraison_action(p_lid uuid, p_action text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); v_me uuid := app.livreur_id(); l public.livraisons%rowtype; c public.commandes%rowtype;
  v_code text; v_m int; v_ecart int; v_pos record; v_motif text := btrim(coalesce(p->>'motif', ''));
  v_etiq boolean; v_req boolean; v_scans jsonb; v_seuil int; v_sig text; v_mobile boolean; v_ref text; v_direct boolean;
begin
  if v_me is null then perform app.deny(); end if;
  select * into l from public.livraisons where id = p_lid and org_id = v_org and livreur_id = v_me for update;
  if not found then raise exception 'Mission introuvable'; end if;
  select * into c from public.commandes where id = l.commande_id for update;
  select coalesce((o.config->>'etiq_scan')::boolean, true), coalesce((o.config->>'signature_seuil')::int, 100000)
    into v_etiq, v_seuil from public.organisations o where o.id = v_org;
  v_req := v_etiq and coalesce(c.nb_colis, 0) > 0;

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
    if v_req then
      v_scans := app.valider_scans(c.id, c.numero, p->'scans', c.nb_colis);
      update public.livraisons set collecte_at = now(), nb_colis = c.nb_colis, etat_colis = left(p->>'etat', 100), colis_scans = v_scans where id = p_lid;
    else
      if coalesce((p->>'nb_colis')::int, 0) < 1 then raise exception 'Nombre de colis invalide'; end if;
      update public.livraisons set collecte_at = now(), nb_colis = (p->>'nb_colis')::int, etat_colis = left(p->>'etat', 100) where id = p_lid;
    end if;

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
    -- Paiement du client à la réception : espèces (le livreur détient l'argent) ou Mobile Money (référence obligatoire ;
    -- « direct » = le client a payé sur le compte d'ANGEL'S GROUP : le livreur ne détient rien et n'a rien à reverser).
    v_mobile := v_m > 0 and app.est_mobile(p->>'mode');
    v_ref := case when v_mobile then nullif(upper(btrim(coalesce(p->>'ref', ''))), '') end;
    v_direct := v_mobile and coalesce((p->>'direct')::boolean, false);
    if v_mobile and (v_ref is null or length(v_ref) < 4) then raise exception 'Référence de la transaction Mobile Money obligatoire (identifiant reçu par SMS)'; end if;
    if v_ref is not null and exists (select 1 from public.fonds where org_id = v_org and upper(btrim(ref)) = v_ref) then raise exception 'Cette référence de transaction est déjà enregistrée'; end if;
    if v_req then v_scans := app.valider_scans(c.id, c.numero, p->'scans', c.nb_colis); end if;
    v_sig := nullif(p->>'signature', '');
    if v_seuil > 0 and c.total >= v_seuil and v_sig is null then raise exception 'Signature du destinataire obligatoire (commande de % F ou plus)', v_seuil; end if;
    if v_sig is not null and (v_sig !~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' or length(v_sig) > 80000) then raise exception 'Signature invalide'; end if;
    perform app.set_statut(c.id, 'livree', 'Livrée — reçu par ' || coalesce(p->>'recu_par', ''));
    select lat, lng into v_pos from public.positions_gps where livreur_id = v_me order by ts desc limit 1;
    update public.livraisons set statut = 'livree', fin_at = now(), recu_par = left(p->>'recu_par', 120), obs = left(p->>'obs', 500),
           montant_encaisse = v_m, mode = p->>'mode', ecart = v_ecart,
           ecart_statut = case when v_ecart <> 0 then 'a_valider' end, ecart_note = case when v_ecart <> 0 then left(p->>'ecart_note', 500) end,
           gps_confirm_lat = v_pos.lat, gps_confirm_lng = v_pos.lng, colis_liv = v_scans, signature = v_sig
     where id = p_lid;
    if v_m > 0 then
      insert into public.fonds(org_id, type, livreur_id, livraison_id, commande_id, montant, mode, ref, direct, par, par_nom)
      values (v_org, 'encaissement', v_me, p_lid, c.id, v_m, p->>'mode', v_ref, v_direct, auth.uid(), (select nom from public.membres where user_id = auth.uid()));
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

-- Soldes : l'argent encaissé « direct » sur le compte d'ANGEL'S GROUP n'est pas détenu par le livreur
create or replace function public.solde_livreurs() returns table (livreur_id uuid, encaisse bigint, reverse bigint, solde bigint)
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (app.has_role('admin', 'direction', 'caissier', 'superviseur') or app.livreur_id() is not null) then perform app.deny(); end if;
  return query
    select l.id, coalesce(sum(f.montant) filter (where f.type = 'encaissement' and not f.direct), 0)::bigint,
           coalesce(sum(f.montant) filter (where f.type = 'reversement'), 0)::bigint,
           (coalesce(sum(f.montant) filter (where f.type = 'encaissement' and not f.direct), 0)
            - coalesce(sum(f.montant) filter (where f.type = 'reversement'), 0))::bigint
    from public.livreurs l left join public.fonds f on f.livreur_id = l.id
    where l.org_id = app.org() and (app.livreur_id() is null or l.id = app.livreur_id())
    group by l.id;
end $f$;

drop function public.reversement(uuid, int, text, text);
create or replace function public.reversement(p_lid uuid, p_montant int, p_mode text, p_note text default '', p_ref text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_solde bigint; v_r text := nullif(upper(btrim(coalesce(p_ref, ''))), '');
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  perform 1 from public.livreurs where id = p_lid and org_id = v_org for update;
  if not found then raise exception 'Livreur introuvable'; end if;
  select coalesce(sum(case when type = 'encaissement' and not direct then montant when type = 'reversement' then -montant end), 0) into v_solde
    from public.fonds where livreur_id = p_lid;
  if p_montant is null or p_montant <= 0 or p_montant > v_solde then raise exception 'Montant invalide (restant à reverser : % F)', v_solde; end if;
  if app.est_mobile(p_mode) then
    if v_r is null or length(v_r) < 4 then raise exception 'Référence de la transaction Mobile Money obligatoire'; end if;
  else v_r := null; end if;
  if v_r is not null and exists (select 1 from public.fonds where org_id = v_org and upper(btrim(ref)) = v_r) then raise exception 'Cette référence de transaction est déjà enregistrée'; end if;
  insert into public.fonds(org_id, type, livreur_id, montant, mode, ref, note, par, par_nom)
  values (v_org, 'reversement', p_lid, p_montant, p_mode, v_r, p_note, auth.uid(), (select nom from public.membres where user_id = auth.uid()));
  perform app.log(v_org, 'Reversement validé', (select nom from public.livreurs where id = p_lid) || ' — ' || p_montant || ' F (reste ' || (v_solde - p_montant) || ' F)');
end $f$;

create table public.versements_declares (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id) on delete cascade,
  montant int not null check (montant > 0),
  mode text not null,
  ref text not null,
  note text,
  statut text not null default 'declare' check (statut in ('declare', 'valide', 'rejete')),
  cree_le timestamptz not null default now(),
  traite_le timestamptz,
  traite_par_nom text,
  motif text
);
create index on public.versements_declares (org_id, statut);
alter table public.versements_declares enable row level security;
create policy versements_select on public.versements_declares for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'caissier')) or livreur_id = (select app.livreur_id())));
grant select on public.versements_declares to authenticated;

create or replace function public.declarer_versement(p_montant int, p_mode text, p_ref text, p_note text default null) returns uuid
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_me uuid := app.livreur_id(); v_solde bigint; v_att bigint; v_r text := nullif(upper(btrim(coalesce(p_ref, ''))), ''); v_id uuid;
begin
  if v_me is null then perform app.deny(); end if;
  if not app.est_mobile(p_mode) then raise exception 'Seul un virement Mobile Money se déclare ; le comptant est remis au caissier'; end if;
  if v_r is null or length(v_r) < 4 then raise exception 'Référence de la transaction obligatoire (identifiant reçu par SMS)'; end if;
  if exists (select 1 from public.fonds where org_id = v_org and upper(btrim(ref)) = v_r)
     or exists (select 1 from public.versements_declares where org_id = v_org and upper(btrim(ref)) = v_r and statut <> 'rejete') then raise exception 'Cette référence de transaction est déjà enregistrée'; end if;
  select coalesce(sum(case when type = 'encaissement' and not direct then montant when type = 'reversement' then -montant end), 0) into v_solde from public.fonds where livreur_id = v_me;
  select coalesce(sum(montant), 0) into v_att from public.versements_declares where livreur_id = v_me and statut = 'declare';
  if p_montant is null or p_montant <= 0 or p_montant > v_solde - v_att then raise exception 'Montant invalide (restant à reverser, hors déclarations en attente : % F)', v_solde - v_att; end if;
  insert into public.versements_declares(org_id, livreur_id, montant, mode, ref, note) values (v_org, v_me, p_montant, p_mode, v_r, left(p_note, 200)) returning id into v_id;
  perform app.log(v_org, 'Versement Mobile Money déclaré', (select nom from public.livreurs where id = v_me) || ' — ' || p_montant || ' F (' || p_mode || ' ' || v_r || ')');
  return v_id;
end $f$;

create or replace function public.traiter_versement(p_id uuid, p_decision text, p_motif text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); d public.versements_declares%rowtype; v_solde bigint; v_nom text := (select nom from public.membres where user_id = auth.uid());
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  select * into d from public.versements_declares where id = p_id and org_id = v_org and statut = 'declare' for update;
  if not found then raise exception 'Déclaration introuvable ou déjà traitée'; end if;
  if p_decision = 'valider' then
    select coalesce(sum(case when type = 'encaissement' and not direct then montant when type = 'reversement' then -montant end), 0) into v_solde from public.fonds where livreur_id = d.livreur_id;
    if d.montant > v_solde then raise exception 'Montant supérieur au restant à reverser (% F)', v_solde; end if;
    insert into public.fonds(org_id, type, livreur_id, montant, mode, ref, note, par, par_nom)
      values (v_org, 'reversement', d.livreur_id, d.montant, d.mode, d.ref, 'Virement déclaré par le livreur, validé par la caisse', auth.uid(), v_nom);
    update public.versements_declares set statut = 'valide', traite_le = now(), traite_par_nom = v_nom where id = p_id;
    perform app.log(v_org, 'Versement Mobile Money validé', d.ref || ' — ' || d.montant || ' F');
  elsif p_decision = 'rejeter' then
    if coalesce(btrim(p_motif), '') = '' then raise exception 'Motif du rejet obligatoire'; end if;
    update public.versements_declares set statut = 'rejete', traite_le = now(), traite_par_nom = v_nom, motif = left(btrim(p_motif), 300) where id = p_id;
    perform app.log(v_org, 'Versement Mobile Money rejeté', d.ref || ' — ' || left(btrim(p_motif), 100));
  else raise exception 'Décision inconnue'; end if;
end $f$;

revoke all on function public.reversement(uuid, int, text, text, text), public.declarer_versement(int, text, text, text), public.traiter_versement(uuid, text, text) from public, anon;
grant execute on function public.reversement(uuid, int, text, text, text), public.declarer_versement(int, text, text, text), public.traiter_versement(uuid, text, text) to authenticated;
