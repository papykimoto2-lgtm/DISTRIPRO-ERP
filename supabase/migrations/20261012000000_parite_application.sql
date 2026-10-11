-- =====================================================================
-- Parité avec l'application : tournées, entretien des motos, documents
-- numérotés, colis étiquetés (QR) et signature de livraison.
-- Dépend de 20261010000000_angels_erp_schema.sql et 20261011000000_notifications.sql
-- Mêmes principes : RLS en lecture, écritures uniquement par RPC contrôlées,
-- documents en ajout seul, vérification des scans et de la signature CÔTÉ SERVEUR.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tournées
-- ---------------------------------------------------------------------
alter table public.compteurs add column tour int not null default 0;

create table public.tournees (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  numero text not null,
  livreur_id uuid not null references public.livreurs(id),
  ts timestamptz not null default now(),
  par uuid default auth.uid(),
  unique (org_id, numero)
);
alter table public.livraisons add column tournee_id uuid references public.tournees(id), add column ordre int;
create index on public.livraisons (tournee_id);
alter table public.tournees enable row level security;
create policy tournees_select on public.tournees for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'superviseur')) or livreur_id = (select app.livreur_id())));

-- Crée la tournée et affecte toutes les commandes dans l'ordre donné : tout ou rien.
create or replace function public.creer_tournee(p_livreur uuid, p_commandes uuid[], p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_t uuid := gen_random_uuid(); v_n int; v_num text; v_cid uuid; v_i int := 0; v_r jsonb;
begin
  if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
  if p_commandes is null or coalesce(array_length(p_commandes, 1), 0) < 2 then raise exception 'Une tournée comprend au moins 2 commandes'; end if;
  if (select count(distinct x) from unnest(p_commandes) x) <> array_length(p_commandes, 1) then raise exception 'Une commande est sélectionnée deux fois'; end if;
  perform 1 from public.livreurs where id = p_livreur and org_id = v_org;
  if not found then raise exception 'Livreur introuvable'; end if;
  for v_cid in select x from unnest(p_commandes) x loop            -- message clair avant toute affectation
    if not exists (select 1 from public.commandes where id = v_cid and org_id = v_org and statut = 'prete') then
      raise exception 'Commande %: elle doit être « prête à être livrée » pour entrer dans une tournée', coalesce((select numero from public.commandes where id = v_cid), v_cid::text);
    end if;
  end loop;
  insert into public.compteurs(org_id, tour) values (v_org, 1) on conflict (org_id) do update set tour = public.compteurs.tour + 1 returning tour into v_n;
  v_num := 'T-' || lpad(v_n::text, 4, '0');
  insert into public.tournees(id, org_id, numero, livreur_id) values (v_t, v_org, v_num, p_livreur);
  foreach v_cid in array p_commandes loop
    v_i := v_i + 1;
    v_r := public.affecter_livraison(v_cid, p_livreur, '', p_force);
    update public.livraisons set tournee_id = v_t, ordre = v_i where id = (v_r->>'livraison_id')::uuid;
  end loop;
  perform app.log(v_org, 'Création tournée', v_num || ' — ' || array_length(p_commandes, 1) || ' livraisons');
  return jsonb_build_object('tournee_id', v_t, 'numero', v_num);
end $f$;

-- Déplace un arrêt d'un cran (-1 / +1), seulement tant que lui et son voisin n'ont pas démarré.
create or replace function public.deplacer_arret(p_livraison uuid, p_dir int) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); s public.livraisons%rowtype; nb public.livraisons%rowtype;
begin
  if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
  if p_dir not in (-1, 1) then raise exception 'Direction invalide'; end if;
  select * into s from public.livraisons where id = p_livraison and org_id = v_org and tournee_id is not null for update;
  if not found then raise exception 'Arrêt de tournée introuvable'; end if;
  select * into nb from public.livraisons
   where tournee_id = s.tournee_id and statut not in ('reaffectee', 'refusee', 'annulee')
     and ((p_dir < 0 and ordre < s.ordre) or (p_dir > 0 and ordre > s.ordre))
   order by case when p_dir < 0 then -ordre else ordre end limit 1 for update;
  if not found then return; end if;
  if s.statut not in ('affectee', 'acceptee') or nb.statut not in ('affectee', 'acceptee') then raise exception 'Arrêt déjà démarré : ordre figé'; end if;
  update public.livraisons set ordre = nb.ordre where id = s.id;
  update public.livraisons set ordre = s.ordre where id = nb.id;
  perform app.log(v_org, 'Ordre de tournée modifié', s.tournee_id::text);
end $f$;

-- ---------------------------------------------------------------------
-- 2. Entretien et réparations des motos
-- ---------------------------------------------------------------------
create table public.entretiens (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  moto_id uuid not null references public.motos(id) on delete cascade,
  ts timestamptz not null default now(),
  type text not null,
  km int not null check (km >= 0),
  cout int not null default 0 check (cout >= 0),
  note text,
  par uuid default auth.uid(),
  par_nom text
);
create index on public.entretiens (moto_id, ts desc);
alter table public.entretiens enable row level security;
create policy entretiens_select on public.entretiens for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'superviseur')));
create trigger entretiens_ajout_seul before update or delete on public.entretiens for each row execute function app.trg_append_only();

create or replace function public.enregistrer_entretien(p_moto uuid, p_date date, p_type text, p_km int, p_cout int, p_prochain_dans int, p_statut text, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); m public.motos%rowtype;
begin
  if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
  if p_statut not in ('disponible', 'immobilisee', 'panne') then raise exception 'Statut de moto invalide'; end if;
  if coalesce(btrim(p_type), '') = '' or p_km is null or p_km < 0 or coalesce(p_cout, 0) < 0 then raise exception 'Intervention invalide'; end if;
  select * into m from public.motos where id = p_moto and org_id = v_org for update;
  if not found then raise exception 'Moto introuvable'; end if;
  insert into public.entretiens(org_id, moto_id, ts, type, km, cout, note, par_nom)
  values (v_org, p_moto, coalesce(p_date, current_date)::timestamptz + interval '12 hours', p_type, p_km, coalesce(p_cout, 0), left(p_note, 500),
          (select nom from public.membres where user_id = auth.uid()));
  update public.motos set km = greatest(km, p_km), prochain_km = case when coalesce(p_prochain_dans, 0) > 0 then p_km + p_prochain_dans else prochain_km end, statut = p_statut where id = p_moto;
  perform app.log(v_org, 'Entretien moto', m.immat || ' — ' || p_type || ' — ' || coalesce(p_cout, 0) || ' F — statut ' || p_statut);
end $f$;

-- ---------------------------------------------------------------------
-- 3. Documents commerciaux numérotés (jamais modifiés ni supprimés)
-- ---------------------------------------------------------------------
create table public.compteurs_docs (
  org_id uuid not null references public.organisations(id) on delete cascade,
  cle text not null,
  n int not null default 0,
  primary key (org_id, cle)
);
alter table public.compteurs_docs enable row level security;

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  type text not null check (type in ('facture', 'recu', 'avoir', 'bl')),
  numero text not null,
  ts timestamptz not null default now(),
  commande_id uuid not null references public.commandes(id),
  cmd_numero text not null,
  client jsonb not null,
  contenu jsonb not null default '{}'::jsonb,       -- copie figée : lignes, totaux, paiements, motif…
  montant int,
  ref_doc uuid references public.documents(id),
  par uuid default auth.uid(),
  par_nom text,
  unique (org_id, numero)
);
create index on public.documents (commande_id, type);
alter table public.documents enable row level security;
create policy documents_select on public.documents for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'direction', 'commercial', 'caissier', 'superviseur'))
  or (type = 'bl' and (select app.has_role('preparateur')))));
create trigger documents_ajout_seul before update or delete on public.documents for each row execute function app.trg_append_only();

create or replace function public.emettre_document(p_commande uuid, p_type text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); c public.commandes%rowtype; cl public.clients%rowtype; v public.vendeurs%rowtype;
  d public.documents%rowtype; f public.documents%rowtype; v_paye int; v_tot int; v_client jsonb; v_lignes jsonb;
  v_contenu jsonb; v_montant int; v_ref uuid; v_pm jsonb; v_reste int; v_cle text; v_n int; v_num text; v_nom text;
begin
  select * into c from public.commandes where id = p_commande and org_id = v_org;
  if not found then raise exception 'Commande introuvable'; end if;
  select * into cl from public.clients where id = c.client_id;
  v_paye := coalesce((select sum(montant) from public.fonds where commande_id = c.id and type in ('acompte', 'encaissement')), 0);

  if p_type = 'facture' then
    if not app.has_role('admin', 'commercial', 'caissier', 'superviseur') then perform app.deny(); end if;
    if c.statut in ('brouillon', 'attente', 'annulee') then raise exception 'Facturation impossible dans cet état de commande'; end if;
    select dd.* into d from public.documents dd where dd.commande_id = p_commande and dd.type = 'facture'
       and dd.montant > coalesce((select sum(a.montant) from public.documents a where a.type = 'avoir' and a.ref_doc = dd.id), 0) order by dd.ts limit 1;
    if found then return to_jsonb(d) || d.contenu; end if;
    if c.vendeur_id is not null then
      select * into v from public.vendeurs where id = c.vendeur_id;
      v_client := jsonb_build_object('nom', v.nom, 'tel', v.tel);
      v_lignes := jsonb_build_array(jsonb_build_object('desig', 'Frais de livraison — ' || (c.adr->>'zone') || ' (' || c.numero || ')', 'qte', 1, 'pu', c.frais));
      v_tot := c.frais; v_paye := 0;
      v_contenu := jsonb_build_object('remise', 0, 'note', 'Facture du service de livraison, établie au nom du vendeur partenaire. Les articles sont facturés par le vendeur.');
    else
      v_client := jsonb_build_object('nom', cl.nom, 'tel', cl.tel);
      select coalesce(jsonb_agg(jsonb_build_object('desig', coalesce(pr.nom, l.desig), 'qte', l.qte, 'pu', l.pu) order by l.ctid), '[]'::jsonb) into v_lignes
        from public.commande_lignes l left join public.produits pr on pr.id = l.produit_id where l.commande_id = c.id;
      if c.frais > 0 then v_lignes := v_lignes || jsonb_build_array(jsonb_build_object('desig', 'Frais de livraison — ' || (c.adr->>'zone'), 'qte', 1, 'pu', c.frais)); end if;
      v_tot := c.total; v_contenu := jsonb_build_object('remise', c.remise);
    end if;
    v_contenu := v_contenu || jsonb_build_object('lignes', v_lignes, 'total', v_tot, 'paye', v_paye, 'solde', greatest(0, v_tot - v_paye));
    v_montant := v_tot;

  elsif p_type = 'recu' then
    if not app.has_role('admin', 'commercial', 'caissier', 'superviseur') then perform app.deny(); end if;
    select jsonb_agg(jsonb_build_object('ts', ts, 'type', type, 'mode', mode, 'montant', montant) order by ts) into v_pm
      from public.fonds where commande_id = c.id and type in ('acompte', 'encaissement');
    if v_pm is null then raise exception 'Aucun paiement enregistré pour cette commande'; end if;
    select dd.* into d from public.documents dd where dd.commande_id = p_commande and dd.type = 'recu' order by dd.ts desc limit 1;
    if found and (d.contenu->>'total_paye')::int = v_paye then return to_jsonb(d) || d.contenu; end if;
    v_client := jsonb_build_object('nom', cl.nom, 'tel', cl.tel);
    v_contenu := jsonb_build_object('paiements', v_pm, 'total_paye', v_paye, 'total', c.total, 'solde', greatest(0, c.total - v_paye));
    v_montant := v_paye;

  elsif p_type = 'avoir' then
    if not app.has_role('admin', 'commercial', 'caissier') then perform app.deny(); end if;
    select * into f from public.documents where id = (p->>'facture')::uuid and org_id = v_org and commande_id = p_commande and type = 'facture';
    if not found then raise exception 'Facture introuvable pour cette commande'; end if;
    v_reste := f.montant - coalesce((select sum(a.montant) from public.documents a where a.type = 'avoir' and a.ref_doc = f.id), 0);
    v_montant := (p->>'montant')::int;
    if v_montant is null or v_montant < 1 or v_montant > v_reste then raise exception 'Montant invalide (maximum %)', v_reste; end if;
    if coalesce(btrim(p->>'motif'), '') = '' then raise exception 'Motif obligatoire'; end if;
    v_ref := f.id; v_client := f.client;
    v_contenu := jsonb_build_object('ref_num', f.numero, 'motif', left(btrim(p->>'motif'), 300), 'montant', v_montant);

  elsif p_type = 'bl' then
    if not app.has_role('admin', 'superviseur', 'commercial', 'preparateur', 'caissier') then perform app.deny(); end if;
    if c.statut not in ('prete', 'affectee', 'en_cours', 'livree', 'echouee', 'retour_cours', 'retour_recu') then raise exception 'Bon de livraison impossible dans cet état de commande'; end if;
    select dd.* into d from public.documents dd where dd.commande_id = p_commande and dd.type = 'bl' order by dd.ts limit 1;
    if found then return to_jsonb(d) || d.contenu; end if;
    select coalesce(jsonb_agg(jsonb_build_object('desig', coalesce(pr.nom, l.desig), 'qte', l.qte) order by l.ctid), '[]'::jsonb) into v_lignes
      from public.commande_lignes l left join public.produits pr on pr.id = l.produit_id where l.commande_id = c.id;
    v_client := jsonb_build_object('nom', cl.nom, 'tel', cl.tel);
    v_contenu := jsonb_build_object('adr', jsonb_build_object('zone', c.adr->>'zone', 'quartier', c.adr->>'quartier', 'repere', c.adr->>'repere'), 'lignes', v_lignes, 'total', c.total);
    v_montant := c.total;
  else
    raise exception 'Type de document inconnu';
  end if;

  v_cle := case p_type when 'facture' then 'FAC' when 'recu' then 'REC' when 'avoir' then 'AVO' else 'BL' end || '-' || extract(year from now())::int;
  insert into public.compteurs_docs(org_id, cle, n) values (v_org, v_cle, 1) on conflict (org_id, cle) do update set n = public.compteurs_docs.n + 1 returning n into v_n;
  v_num := v_cle || '-' || lpad(v_n::text, 4, '0');
  select nom into v_nom from public.membres where user_id = auth.uid();
  insert into public.documents(org_id, type, numero, commande_id, cmd_numero, client, contenu, montant, ref_doc, par_nom)
  values (v_org, p_type, v_num, c.id, c.numero, v_client, v_contenu, v_montant, v_ref, v_nom) returning * into d;
  perform app.log(v_org, 'Émission document', v_num || ' — ' || c.numero);
  return to_jsonb(d) || d.contenu;
end $f$;

-- ---------------------------------------------------------------------
-- 4. Colis étiquetés (QR), vérification des scans et signature
-- ---------------------------------------------------------------------
alter table public.commandes add column nb_colis int;     -- visible du livreur : « cette commande a N étiquettes »
create table public.colis (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid not null references public.commandes(id) on delete cascade,
  n int not null,
  tok text not null,                                      -- jamais lisible du livreur : seul le serveur vérifie
  unique (commande_id, n)
);
alter table public.colis enable row level security;
create policy colis_select on public.colis for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'commercial', 'preparateur')));
alter table public.livraisons add column colis_scans jsonb, add column colis_liv jsonb, add column signature text;

create or replace function public.etiqueter_commande(p_commande uuid, p_nb int) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.commandes%rowtype; v_alpha constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  if not app.has_role('admin', 'preparateur', 'superviseur', 'commercial') then perform app.deny(); end if;
  if p_nb is null or p_nb < 1 or p_nb > 20 then raise exception 'Nombre de colis invalide (1 à 20)'; end if;
  select * into c from public.commandes where id = p_commande and org_id = v_org for update;
  if not found then raise exception 'Commande introuvable'; end if;
  if c.statut not in ('confirmee', 'preparation', 'prete', 'affectee', 'en_cours') then raise exception 'Étiquetage impossible dans cet état de commande'; end if;
  if coalesce(c.nb_colis, 0) <> p_nb then
    if exists (select 1 from public.livraisons where commande_id = p_commande and (colis_scans is not null or colis_liv is not null)) then
      raise exception 'Des colis ont déjà été scannés : le nombre ne peut plus changer';
    end if;
    delete from public.colis where commande_id = p_commande;
    for i in 1..p_nb loop
      insert into public.colis(org_id, commande_id, n, tok)
      values (v_org, p_commande, i, (select string_agg(substr(v_alpha, 1 + (get_byte(decode(substr(replace(gen_random_uuid()::text, '-', ''), 1, 2), 'hex'), 0) % 32), 1), '') from generate_series(1, 5)));
    end loop;
    update public.commandes set nb_colis = p_nb where id = p_commande;
  end if;
  perform app.log(v_org, 'Étiquettes colis imprimées', c.numero || ' — ' || p_nb || ' colis');
  return (select jsonb_agg(jsonb_build_object('n', n, 'tok', tok) order by n) from public.colis where commande_id = p_commande);
end $f$;

-- Analyse d'un texte scanné (QR « AGE1|commande|n/total|code » ou code court de 5 caractères).
create or replace function app.analyser_colis(p_cid uuid, p_numero text, p_txt text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare m text[]; v_n int;
begin
  p_txt := btrim(coalesce(p_txt, ''));
  m := regexp_match(p_txt, '^AGE1\|([^|]+)\|(\d+)/(\d+)\|([A-Z0-9]{5})$');
  if m is not null then
    if m[1] <> p_numero then return jsonb_build_object('ok', false, 'msg', 'Ce colis appartient à la commande ' || m[1] || ', pas à ' || p_numero); end if;
    select n into v_n from public.colis where commande_id = p_cid and n = m[2]::int and tok = m[4];
    if found then return jsonb_build_object('ok', true, 'n', v_n, 'mode', 'scan'); end if;
    return jsonb_build_object('ok', false, 'msg', 'Étiquette invalide ou périmée pour ' || p_numero);
  end if;
  if p_txt ~ '^[A-Za-z0-9]{5}$' then
    select n into v_n from public.colis where commande_id = p_cid and tok = upper(p_txt);
    if found then return jsonb_build_object('ok', true, 'n', v_n, 'mode', 'saisie'); end if;
    return jsonb_build_object('ok', false, 'msg', 'Code inconnu pour cette commande');
  end if;
  return jsonb_build_object('ok', false, 'msg', 'QR non reconnu (étiquette de l''entreprise attendue)');
end $f$;

-- Tous les colis doivent être couverts, une seule fois chacun ; sinon exception explicite.
create or replace function app.valider_scans(p_cid uuid, p_numero text, p_scans jsonb, p_total int) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare t text; r jsonb; v_seen int[] := '{}'; v_out jsonb := '[]'::jsonb;
begin
  if p_scans is null or jsonb_typeof(p_scans) <> 'array' then raise exception 'Scannez les colis (% étiquette(s))', p_total; end if;
  for t in select jsonb_array_elements_text(p_scans) loop
    r := app.analyser_colis(p_cid, p_numero, t);
    if not (r->>'ok')::boolean then raise exception '%', r->>'msg'; end if;
    if (r->>'n')::int = any(v_seen) then continue; end if;
    v_seen := v_seen || (r->>'n')::int;
    v_out := v_out || jsonb_build_array(jsonb_build_object('n', (r->>'n')::int, 'ts', now(), 'mode', r->>'mode'));
  end loop;
  if coalesce(array_length(v_seen, 1), 0) < p_total then raise exception 'Il reste % colis à scanner', p_total - coalesce(array_length(v_seen, 1), 0); end if;
  return v_out;
end $f$;

-- Retour immédiat pour l'écran de scan (livreur sur sa mission, ou personnel).
create or replace function public.verifier_colis(p_commande uuid, p_texte text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes where id = p_commande and org_id = app.org();
  if not found then raise exception 'Commande introuvable'; end if;
  if not (app.has_role('admin', 'superviseur', 'commercial', 'preparateur') or app.livreur_voit_commande(p_commande)) then perform app.deny(); end if;
  return app.analyser_colis(c.id, c.numero, p_texte);
end $f$;

-- Actions du livreur : même fonction qu'avant, avec contrôle des scans (prise en charge et remise) et de la signature.
create or replace function public.livraison_action(p_lid uuid, p_action text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); v_me uuid := app.livreur_id(); l public.livraisons%rowtype; c public.commandes%rowtype;
  v_code text; v_m int; v_ecart int; v_pos record; v_motif text := btrim(coalesce(p->>'motif', ''));
  v_etiq boolean; v_req boolean; v_scans jsonb; v_seuil int; v_sig text;
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

-- ---------------------------------------------------------------------
-- 5. Lectures calculées que l'écran ne peut pas déduire des tables (droits restreints)
-- ---------------------------------------------------------------------
-- Montant déjà payé par commande visible (acompte + encaissements) : le vendeur et le livreur ne lisent pas la table des fonds.
create or replace function public.soldes_commandes() returns table (commande_id uuid, paye bigint)
language sql stable security definer set search_path = '' as $f$
  select c.id, coalesce(sum(f.montant) filter (where f.type in ('acompte', 'encaissement')), 0)::bigint
  from public.commandes c left join public.fonds f on f.commande_id = c.id
  where c.org_id = app.org() and (
        app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur', 'caissier')
     or (c.vendeur_id is not null and c.vendeur_id = app.vendeur_id())
     or app.livreur_voit_commande(c.id))
  group by c.id
$f$;

-- Commandes qui composent le montant dû à un vendeur (livrées, non payées au vendeur, entièrement réglées par le client).
create or replace function public.vendeur_eligibles(p_vid uuid default null) returns table (vendeur_id uuid, commande_id uuid, numero text, net bigint, livree_le timestamptz)
language plpgsql stable security definer set search_path = '' as $f$
declare v_target uuid := p_vid;
begin
  if app.role() = 'vendeur' then v_target := app.vendeur_id();
  elsif not app.has_role('admin', 'direction', 'caissier', 'commercial', 'superviseur') then perform app.deny(); end if;
  return query
    select v.id, c.id, c.numero, round((c.montant_produits - c.remise) * (1 - v.commission_pct / 100))::bigint,
           (select max(l.fin_at) from public.livraisons l where l.commande_id = c.id and l.statut = 'livree')
    from public.vendeurs v join public.commandes c on c.vendeur_id = v.id
    where v.org_id = app.org() and (v_target is null or v.id = v_target)
      and c.statut = 'livree' and not c.vendeur_encaisse and app.solde_commande(c.id) = 0
    order by 5 desc;
end $f$;

-- ---------------------------------------------------------------------
-- 6. Privilèges
-- ---------------------------------------------------------------------
revoke all on public.tournees, public.entretiens, public.compteurs_docs, public.documents, public.colis from anon, authenticated;
grant select on public.tournees, public.entretiens, public.documents, public.colis to authenticated;
do $f$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('app', 'public') and p.proname in ('creer_tournee', 'deplacer_arret', 'enregistrer_entretien', 'emettre_document',
             'etiqueter_commande', 'analyser_colis', 'valider_scans', 'verifier_colis', 'soldes_commandes', 'vendeur_eligibles') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $f$;
grant execute on function app.analyser_colis(uuid, text, text), app.valider_scans(uuid, text, jsonb, int) to authenticated;
grant execute on function
  public.creer_tournee(uuid, uuid[], boolean), public.deplacer_arret(uuid, int),
  public.enregistrer_entretien(uuid, date, text, int, int, int, text, text), public.emettre_document(uuid, text, jsonb),
  public.etiqueter_commande(uuid, int), public.verifier_colis(uuid, text), public.soldes_commandes(), public.vendeur_eligibles(uuid)
  to authenticated;
