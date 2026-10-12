-- Zones de livraison : Grand Abidjan complet et périphérie (Bingerville, Anyama, Songon, Grand-Bassam, Dabou…).
-- Les zones sont ajoutées sans écraser ni supprimer celles que l'administrateur a déjà modifiées.

create or replace function app.zones_defaut(p_org uuid) returns void
language sql security definer set search_path = '' as $f$
  insert into public.zones(org_id, nom, frais, delai_min) values
    (p_org, 'Plateau', 1500, 40),
    (p_org, 'Cocody', 1500, 45),
    (p_org, 'Marcory', 1500, 40),
    (p_org, 'Treichville', 1500, 40),
    (p_org, 'Adjamé', 1500, 40),
    (p_org, 'Koumassi', 2000, 50),
    (p_org, 'Attécoubé', 2000, 50),
    (p_org, 'Abobo', 2000, 60),
    (p_org, 'Yopougon', 2000, 60),
    (p_org, 'Port-Bouët', 2500, 60),
    (p_org, 'Bingerville', 3000, 60),
    (p_org, 'Anyama', 3000, 70),
    (p_org, 'Songon', 3500, 75),
    (p_org, 'Grand-Bassam', 4500, 90),
    (p_org, 'Dabou', 4500, 90),
    (p_org, 'Bonoua', 5000, 100),
    (p_org, 'Azaguié', 5000, 100),
    (p_org, 'Alépé', 6000, 110),
    (p_org, 'Sikensi', 6000, 110),
    (p_org, 'Jacqueville', 6000, 120),
    (p_org, 'Assinie', 7000, 130),
    (p_org, 'Autre localité (tarif à convenir)', 6000, 120)
  on conflict (org_id, nom) do nothing;
$f$;
revoke all on function app.zones_defaut(uuid) from public, anon, authenticated;

-- Sociétés existantes : ajout des zones manquantes (une seule fois, à l'installation de cette migration)
select app.zones_defaut(id) from public.organisations;

-- Nouvelles sociétés : même liste
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
  perform app.zones_defaut(v_org);
  return v_org;
end $f$;

-- Adresse de collecte du fournisseur : position GPS validée et conservée quand l'adresse est modifiée sans position
create or replace function public.maj_adresse_collecte(p jsonb, p_vendeur uuid default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_id uuid; v_lat numeric; v_lng numeric;
begin
  if app.role() = 'vendeur' then v_id := app.vendeur_id();
  elsif app.has_role('admin', 'superviseur', 'commercial') then v_id := p_vendeur;
  else perform app.deny(); end if;
  if v_id is null or not exists (select 1 from public.vendeurs where id = v_id and org_id = v_org) then raise exception 'Vendeur introuvable'; end if;
  if coalesce(btrim(p->>'zone'), '') = '' or (coalesce(btrim(p->>'quartier'), '') = '' and coalesce(btrim(p->>'repere'), '') = '' and p->>'lat' is null) then raise exception 'Indiquez la zone et le quartier ou un point de repère'; end if;
  if p->>'lat' is not null and p->>'lng' is not null then
    v_lat := round((p->>'lat')::numeric, 6); v_lng := round((p->>'lng')::numeric, 6);
    if v_lat not between -90 and 90 or v_lng not between -180 and 180 then raise exception 'Position GPS invalide'; end if;
  else  -- adresse modifiée sans position (ex. par l'équipe) : la position déjà enregistrée est conservée
    select (adresse_collecte->>'lat')::numeric, (adresse_collecte->>'lng')::numeric into v_lat, v_lng from public.vendeurs where id = v_id;
  end if;
  update public.vendeurs set adresse_collecte = jsonb_build_object('zone', left(btrim(p->>'zone'), 60), 'quartier', left(coalesce(btrim(p->>'quartier'), ''), 80),
    'repere', left(coalesce(btrim(p->>'repere'), ''), 120), 'lat', v_lat, 'lng', v_lng) where id = v_id;
  perform app.log(v_org, 'Adresse de collecte mise à jour', (select nom from public.vendeurs where id = v_id));
end $f$;
