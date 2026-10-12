-- Collecte : un incident est ouvert automatiquement à la réception pour chaque écart (colis manquants, commande non remise, colis en trop).

create or replace function app.incident_auto(p_org uuid, p_cat text, p_commande uuid, p_descr text) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_n int; v_ref text;
begin
  insert into public.compteurs(org_id, inc) values (p_org, 1) on conflict (org_id) do update set inc = public.compteurs.inc + 1 returning inc into v_n;
  v_ref := 'INC-' || lpad(v_n::text, 4, '0');
  insert into public.incidents(org_id, ref, cat, commande_id, par_user, par_nom, descr)
    values (p_org, v_ref, p_cat, p_commande, auth.uid(), coalesce((select nom from public.membres where user_id = auth.uid()), 'Système'), left(p_descr, 2000));
  perform app.log(p_org, 'Incident ouvert automatiquement', v_ref || ' — ' || p_cat);
  return v_ref;
end $f$;

create or replace function public.collecte_action(p_collecte uuid, p_action text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.collectes%rowtype; v_code text; v_nom text := (select nom from public.membres where user_id = auth.uid());
        r record; v_n int; v_tot int := 0; v_liv uuid; v_inc int := 0; v_vnom text;
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
    select nom into v_vnom from public.vendeurs where id = c.vendeur_id;
    for r in select cc.commande_id, cc.colis_collectes, co.statut as cstat, co.numero as cnum from public.collecte_commandes cc join public.commandes co on co.id = cc.commande_id where cc.collecte_id = c.id loop
      v_n := coalesce((p -> 'recus' ->> r.commande_id::text)::int, r.colis_collectes, 0);
      if v_n < 0 then raise exception 'Nombre de colis invalide'; end if;
      update public.collecte_commandes set colis_recus = v_n where collecte_id = c.id and commande_id = r.commande_id;
      if coalesce(r.colis_collectes, 0) > 0 and v_n >= r.colis_collectes and r.cstat = 'confirmee' then
        perform public.commande_action(r.commande_id, 'preparer');
      end if;
      -- Écarts : un incident est ouvert automatiquement (colis manquants, commande non remise, colis en trop).
      if coalesce(r.colis_collectes, 0) = 0 then
        perform app.incident_auto(v_org, 'Colis manquant', r.commande_id, format('Collecte %s chez %s : la commande %s n''a pas été remise par le fournisseur (0 colis collecté). La commande reste « confirmée ».', c.numero, v_vnom, r.cnum)); v_inc := v_inc + 1;
      elsif v_n < r.colis_collectes then
        perform app.incident_auto(v_org, 'Colis manquant', r.commande_id, format('Collecte %s chez %s : %s colis reçu(s) au dépôt sur %s collecté(s) pour la commande %s (%s manquant(s)). La commande reste « confirmée ».', c.numero, v_vnom, v_n, r.colis_collectes, r.cnum, r.colis_collectes - v_n)); v_inc := v_inc + 1;
      elsif v_n > r.colis_collectes then
        perform app.incident_auto(v_org, 'Écart de colis', r.commande_id, format('Collecte %s chez %s : %s colis reçu(s) au dépôt pour %s collecté(s) sur la commande %s (%s en trop).', c.numero, v_vnom, v_n, r.colis_collectes, r.cnum, v_n - r.colis_collectes)); v_inc := v_inc + 1;
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
  return jsonb_build_object('ok', true, 'incidents', v_inc);
end $f$;
