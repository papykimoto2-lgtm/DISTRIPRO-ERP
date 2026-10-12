-- Commande par le client lui-même : lien/QR personnel du fournisseur → demande (articles, captures, prix proposé, position GPS)
-- que le fournisseur contrôle puis transforme en commande. Le client n'a pas de compte : le lien contient un secret de 256 bits.
-- Rien n'est créé en commande tant que le fournisseur n'a pas validé : le client ne fixe jamais un prix de lui-même.

create table public.commande_liens (
  token text primary key default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  org_id uuid not null references public.organisations(id) on delete cascade,
  vendeur_id uuid not null unique references public.vendeurs(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '1 year'
);
alter table public.commande_liens enable row level security;          -- aucune politique : accès uniquement par les fonctions

create table public.demandes_commande (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  vendeur_id uuid not null references public.vendeurs(id) on delete cascade,
  nom text not null check (char_length(nom) between 1 and 80),
  tel text not null check (char_length(tel) between 6 and 20),
  zone text not null,
  quartier text check (char_length(quartier) <= 120),
  repere text check (char_length(repere) <= 200),
  lat numeric(9,6) check (lat between -90 and 90),
  lng numeric(9,6) check (lng between -180 and 180),
  lignes jsonb not null,
  photos jsonb not null default '[]'::jsonb,
  note text check (char_length(note) <= 500),
  statut text not null default 'nouvelle' check (statut in ('nouvelle', 'traitee', 'rejetee')),
  commande_id uuid references public.commandes(id) on delete set null,
  motif text check (char_length(motif) <= 300),
  cree_le timestamptz not null default now()
);
create index on public.demandes_commande (org_id, vendeur_id, statut, cree_le desc);
alter table public.demandes_commande enable row level security;
create policy demandes_select on public.demandes_commande for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur', 'commercial', 'direction')) or vendeur_id = (select app.vendeur_id())));
grant select on public.demandes_commande to authenticated;

-- Le fournisseur (ou l'équipe ANGEL'S) obtient / renouvelle le lien. Renouveler invalide l'ancien lien.
create or replace function public.creer_lien_commande(p_vendeur uuid default null, p_renouveler boolean default false) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_vend uuid; v_token text;
begin
  if app.role() = 'vendeur' then v_vend := app.vendeur_id();
  elsif app.has_role('admin', 'superviseur', 'commercial') then v_vend := p_vendeur;
  else perform app.deny(); end if;
  if v_vend is null or not exists (select 1 from public.vendeurs where id = v_vend and org_id = v_org) then raise exception 'Vendeur introuvable'; end if;
  if p_renouveler then delete from public.commande_liens where vendeur_id = v_vend; end if;
  insert into public.commande_liens(org_id, vendeur_id) values (v_org, v_vend)
    on conflict (vendeur_id) do update set expires_at = greatest(public.commande_liens.expires_at, now() + interval '1 year')
    returning token into v_token;
  return v_token;
end $f$;

-- Page publique : nom du fournisseur et zones desservies (rien d'autre)
create or replace function public.commande_lien_get(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare l public.commande_liens%rowtype; v public.vendeurs%rowtype; o public.organisations%rowtype;
begin
  select * into l from public.commande_liens where token = p_token and expires_at > now();
  if not found then return null; end if;
  select * into v from public.vendeurs where id = l.vendeur_id;
  select * into o from public.organisations where id = l.org_id;
  return jsonb_build_object('org', o.nom, 'w', o.whatsapp, 'vendeur', v.nom,
    'zones', (select coalesce(jsonb_agg(jsonb_build_object('nom', z.nom, 'frais', z.frais) order by z.nom), '[]'::jsonb) from public.zones z where z.org_id = l.org_id));
end $f$;

-- Dépôt d'une demande par le client (sans compte). Contrôles stricts + limite de débit.
create or replace function public.demande_deposer(p_token text, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare l public.commande_liens%rowtype; v_tel text := regexp_replace(coalesce(p->>'tel', ''), '[^0-9+]', '', 'g');
        v_nom text := btrim(coalesce(p->>'nom', '')); v_lat numeric; v_lng numeric; v_lignes jsonb; v_photos jsonb; v_id uuid;
        v_z text := p->>'zone'; x jsonb;
begin
  select * into l from public.commande_liens where token = p_token and expires_at > now();
  if not found then raise exception 'Lien expiré ou invalide'; end if;
  if v_nom = '' or length(v_nom) > 80 then raise exception 'Indiquez votre nom'; end if;
  if length(v_tel) < 8 or length(v_tel) > 16 then raise exception 'Indiquez un numéro de téléphone valide'; end if;
  if not exists (select 1 from public.zones where org_id = l.org_id and nom = v_z) then raise exception 'Choisissez votre zone de livraison'; end if;
  if coalesce(btrim(p->>'quartier'), '') = '' and coalesce(btrim(p->>'repere'), '') = '' and p->>'lat' is null then
    raise exception 'Indiquez votre quartier, un point de repère ou envoyez votre position';
  end if;
  if p->>'lat' is not null then
    v_lat := round((p->>'lat')::numeric, 6); v_lng := round((p->>'lng')::numeric, 6);
    if v_lat not between -90 and 90 or v_lng not between -180 and 180 then raise exception 'Position GPS invalide'; end if;
  end if;
  if jsonb_typeof(p->'lignes') <> 'array' or jsonb_array_length(p->'lignes') not between 1 and 30 then raise exception 'Ajoutez 1 à 30 articles'; end if;
  select jsonb_agg(jsonb_build_object('desig', left(btrim(x.desig), 120), 'qte', x.qte, 'pu', x.pu, 'img', x.img)) into v_lignes
    from jsonb_to_recordset(p->'lignes') as x(desig text, qte int, pu int, img int);
  if exists (select 1 from jsonb_to_recordset(v_lignes) as x(desig text, qte int, pu int, img int)
      where coalesce(x.desig, '') = '' or x.qte is null or x.qte not between 1 and 9999 or (x.pu is not null and x.pu not between 0 and 100000000)) then
    raise exception 'Articles invalides (désignation et quantité requises)';
  end if;
  v_photos := coalesce(p->'photos', '[]'::jsonb);
  if jsonb_typeof(v_photos) <> 'array' or jsonb_array_length(v_photos) > 6 then raise exception 'Maximum 6 photos'; end if;
  for x in select * from jsonb_array_elements(v_photos) loop
    if jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^data:image/(jpeg|png|webp);base64,' or length(x #>> '{}') > 600000 then raise exception 'Photo invalide ou trop lourde'; end if;
  end loop;
  -- limite de débit : 5 demandes par heure et par téléphone, 40 par heure et par fournisseur
  if (select count(*) from public.demandes_commande where vendeur_id = l.vendeur_id and tel = v_tel and cree_le > now() - interval '1 hour') >= 5
     or (select count(*) from public.demandes_commande where vendeur_id = l.vendeur_id and cree_le > now() - interval '1 hour') >= 40 then
    raise exception 'Trop de demandes envoyées : réessayez plus tard ou contactez votre fournisseur';
  end if;
  insert into public.demandes_commande(org_id, vendeur_id, nom, tel, zone, quartier, repere, lat, lng, lignes, photos, note)
    values (l.org_id, l.vendeur_id, v_nom, v_tel, v_z, left(btrim(coalesce(p->>'quartier', '')), 120), left(btrim(coalesce(p->>'repere', '')), 200),
            v_lat, v_lng, v_lignes, v_photos, nullif(left(btrim(coalesce(p->>'note', '')), 500), ''))
    returning id into v_id;
  perform app.log(l.org_id, 'Demande de commande client reçue', v_nom);
  return jsonb_build_object('ok', true, 'ref', upper(left(replace(v_id::text, '-', ''), 6)));
end $f$;

-- Le fournisseur marque la demande : traitée (liée à la commande créée) ou rejetée (motif)
create or replace function public.demande_traiter(p_id uuid, p_action text, p_commande uuid default null, p_motif text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare d public.demandes_commande%rowtype; v_org uuid := app.org();
begin
  select * into d from public.demandes_commande where id = p_id and org_id = v_org;
  if not found then raise exception 'Demande introuvable'; end if;
  if not (app.has_role('admin', 'superviseur', 'commercial') or coalesce(app.role() = 'vendeur' and d.vendeur_id = app.vendeur_id(), false)) then perform app.deny(); end if;
  if d.statut <> 'nouvelle' then raise exception 'Demande déjà traitée'; end if;
  if p_action = 'traitee' then
    if p_commande is not null and not exists (select 1 from public.commandes where id = p_commande and org_id = v_org and vendeur_id = d.vendeur_id) then raise exception 'Commande introuvable'; end if;
    update public.demandes_commande set statut = 'traitee', commande_id = p_commande where id = p_id;
  elsif p_action = 'rejetee' then
    update public.demandes_commande set statut = 'rejetee', motif = nullif(left(btrim(coalesce(p_motif, '')), 300), '') where id = p_id;
  else raise exception 'Action invalide'; end if;
  perform app.log(v_org, 'Demande de commande client ' || p_action, d.nom);
end $f$;

revoke all on function public.creer_lien_commande(uuid, boolean), public.commande_lien_get(text), public.demande_deposer(text, jsonb), public.demande_traiter(uuid, text, uuid, text) from public, anon;
grant execute on function public.creer_lien_commande(uuid, boolean), public.demande_traiter(uuid, text, uuid, text) to authenticated;
grant execute on function public.commande_lien_get(text), public.demande_deposer(text, jsonb) to anon, authenticated;

-- Dépôt par le fournisseur : accepte désormais la position GPS du client (adresse.lat / adresse.lng, facultatives)
create or replace function public.vendeur_deposer_commande(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); v_vend uuid := app.vendeur_id(); v_cl uuid; v_ad uuid; v_z record;
  v_tel text := regexp_replace(coalesce(p#>>'{client,tel}', ''), '\s', '', 'g'); v_lignes jsonb; v_prods int;
  v_pv int; v_id uuid; v_num text; v_lat numeric; v_lng numeric;
begin
  if v_vend is null then perform app.deny(); end if;
  if coalesce(btrim(p#>>'{client,nom}'), '') = '' or v_tel = '' then raise exception 'Nom et téléphone du client requis'; end if;
  if p#>>'{adresse,lat}' is not null and p#>>'{adresse,lng}' is not null then
    v_lat := round((p#>>'{adresse,lat}')::numeric, 6); v_lng := round((p#>>'{adresse,lng}')::numeric, 6);
    if v_lat not between -90 and 90 or v_lng not between -180 and 180 then raise exception 'Position GPS invalide'; end if;
  end if;
  select * into v_z from public.zones where org_id = v_org and nom = p#>>'{adresse,zone}';
  if not found then raise exception 'Zone inconnue'; end if;
  if coalesce(btrim(p#>>'{adresse,quartier}'), '') = '' and coalesce(btrim(p#>>'{adresse,repere}'), '') = '' and p#>>'{adresse,lat}' is null then
    raise exception 'Indiquez le quartier ou un point de repère';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('desig', btrim(x.desig), 'qte', x.qte, 'pu', x.pu)), '[]'::jsonb) into v_lignes
    from jsonb_to_recordset(p->'lignes') as x(desig text, qte int, pu int);
  if jsonb_array_length(v_lignes) = 0 or exists (select 1 from jsonb_to_recordset(v_lignes) as x(desig text, qte int, pu int)
       where coalesce(x.desig, '') = '' or x.qte is null or x.qte <= 0 or x.pu is null or x.pu < 0) then
    raise exception 'Articles invalides (désignation, quantité et prix requis)';
  end if;
  select coalesce(sum(x.qte * x.pu), 0) into v_prods from jsonb_to_recordset(v_lignes) as x(desig text, qte int, pu int);
  -- Paiement du client final : chez le fournisseur (tout ou partie des articles) et/ou chez le livreur désigné par ANGEL'S GROUP.
  v_pv := case coalesce(p->>'pay', 'livraison') when 'paye' then v_prods when 'partiel' then coalesce((p->>'paye_vendeur')::int, 0) else 0 end;
  if v_pv < 0 or v_pv > v_prods then raise exception 'Le montant payé au vendeur doit être compris entre 0 et le prix des articles (% F)', v_prods; end if;
  if coalesce(p->>'pay', 'livraison') = 'partiel' and v_pv = 0 then raise exception 'Indiquez le montant déjà payé au vendeur'; end if;

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
    insert into public.adresses(org_id, client_id, libelle, zone, quartier, repere, instructions, defaut, lat, lng, gps_src, gps_ts)
    values (v_org, v_cl, 'Livraison', v_z.nom, btrim(coalesce(p#>>'{adresse,quartier}', '')), btrim(coalesce(p#>>'{adresse,repere}', '')),
            btrim(coalesce(p#>>'{adresse,instructions}', '')), not exists (select 1 from public.adresses where client_id = v_cl),
            v_lat, v_lng, case when v_lat is not null then 'client' end, case when v_lat is not null then now() end)
    returning id into v_ad;
  elsif v_lat is not null then
    update public.adresses set lat = v_lat, lng = v_lng, gps_src = 'client', gps_ts = now() where id = v_ad and lat is null;
  end if;
  v_id := app.insert_commande(v_org, v_vend, v_cl, v_ad, v_lignes, v_z.frais, 0,
            case when v_pv > 0 then 'partiel' else 'livraison' end, v_pv,
            case when v_pv > 0 then 'Payé au vendeur' else 'Espèces' end, 'normale', 'Vendeur partenaire', left(p->>'obs', 500), v_pv >= v_prods and v_prods > 0);
  update public.commandes set paye_vendeur = v_pv where id = v_id;
  perform app.set_statut(v_id, 'attente', 'Commande déposée par le vendeur');
  select numero into v_num from public.commandes where id = v_id;
  perform app.log(v_org, 'Commande vendeur déposée', v_num);
  return jsonb_build_object('id', v_id, 'numero', v_num);
end $f$;
