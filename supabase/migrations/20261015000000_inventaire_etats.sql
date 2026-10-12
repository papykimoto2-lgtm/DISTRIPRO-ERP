-- Entrées de stock, inventaires physiques, journal des mouvements et état périodique des stocks.
-- Le stock ne se modifie jamais en direct : tout passe par app.stock_mvt (mouvements en ajout seul).

alter table public.produits add column cout int not null default 0 check (cout >= 0);     -- coût d'achat unitaire (valorisation du stock)
grant insert (cout), update (cout) on public.produits to authenticated;

-- ---------------------------------------------------------------------
-- Entrée de marchandise (réception fournisseur, retour client hors commande…)
-- ---------------------------------------------------------------------
create or replace function public.recevoir_stock(p_produit uuid, p_qte int, p_ref text default null, p_cout int default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_nom text;
begin
  if not app.has_role('admin', 'commercial', 'preparateur') then perform app.deny(); end if;
  if p_qte is null or p_qte <= 0 then raise exception 'Quantité invalide'; end if;
  if coalesce(btrim(p_ref), '') = '' then raise exception 'Référence de réception obligatoire (bon de livraison fournisseur, facture…)'; end if;
  select nom into v_nom from public.produits where id = p_produit and org_id = v_org for update;
  if not found then raise exception 'Produit introuvable'; end if;
  perform app.stock_mvt(v_org, p_produit, p_qte, 'entree', left(btrim(p_ref), 120));
  if p_cout is not null and p_cout >= 0 then update public.produits set cout = p_cout where id = p_produit; end if;
  perform app.log(v_org, 'Entrée de stock', v_nom || ' +' || p_qte || ' — ' || left(btrim(p_ref), 120));
end $f$;

-- ---------------------------------------------------------------------
-- Inventaires physiques
-- ---------------------------------------------------------------------
create table public.inventaires (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  numero text not null,
  statut text not null default 'ouvert' check (statut in ('ouvert', 'valide', 'annule')),
  note text,
  cree_le timestamptz not null default now(),
  cree_par_nom text,
  clos_le timestamptz,
  clos_par_nom text,
  motif_annulation text,
  unique (org_id, numero)
);
create unique index inventaire_un_ouvert on public.inventaires (org_id) where statut = 'ouvert';

create table public.inventaire_lignes (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organisations(id) on delete cascade,
  inventaire_id uuid not null references public.inventaires(id) on delete cascade,
  produit_id uuid not null references public.produits(id),
  theorique int not null,
  compte int check (compte is null or compte >= 0),
  note text,
  compte_par_nom text,
  unique (inventaire_id, produit_id)
);

alter table public.inventaires enable row level security;
alter table public.inventaire_lignes enable row level security;
create policy inv_select on public.inventaires for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur')));
create policy invl_select on public.inventaire_lignes for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur')));
grant select on public.inventaires, public.inventaire_lignes to authenticated;

-- Un inventaire validé ou annulé ne change plus jamais.
create or replace function app.trg_inventaire_fige() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  if tg_table_name = 'inventaires' then
    if tg_op = 'DELETE' then raise exception 'Un inventaire ne se supprime pas'; end if;
    if old.statut <> 'ouvert' then raise exception 'Inventaire clos : modification interdite'; end if;
  else
    if (select statut from public.inventaires where id = coalesce(new.inventaire_id, old.inventaire_id)) <> 'ouvert' then raise exception 'Inventaire clos : modification interdite'; end if;
  end if;
  return coalesce(new, old);
end $f$;
create trigger inv_fige before update or delete on public.inventaires for each row execute function app.trg_inventaire_fige();
create trigger invl_fige before update or delete on public.inventaire_lignes for each row execute function app.trg_inventaire_fige();

create or replace function public.ouvrir_inventaire(p_note text default null) returns uuid
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_id uuid := gen_random_uuid(); v_cle text; v_n int; v_nom text;
begin
  if not app.has_role('admin', 'commercial', 'preparateur') then perform app.deny(); end if;
  if exists (select 1 from public.inventaires where org_id = v_org and statut = 'ouvert') then raise exception 'Un inventaire est déjà ouvert : validez-le ou annulez-le d''abord'; end if;
  v_cle := 'INV-' || extract(year from now())::int;
  insert into public.compteurs_docs(org_id, cle, n) values (v_org, v_cle, 1) on conflict (org_id, cle) do update set n = public.compteurs_docs.n + 1 returning n into v_n;
  select nom into v_nom from public.membres where user_id = auth.uid();
  insert into public.inventaires(id, org_id, numero, note, cree_par_nom) values (v_id, v_org, v_cle || '-' || lpad(v_n::text, 4, '0'), left(p_note, 300), v_nom);
  insert into public.inventaire_lignes(org_id, inventaire_id, produit_id, theorique) select v_org, v_id, id, stock from public.produits where org_id = v_org and actif;
  perform app.log(v_org, 'Inventaire ouvert', v_cle || '-' || lpad(v_n::text, 4, '0'));
  return v_id;
end $f$;

create or replace function public.saisir_comptage(p_inventaire uuid, p_produit uuid, p_compte int, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org();
begin
  if not app.has_role('admin', 'commercial', 'preparateur') then perform app.deny(); end if;
  if p_compte is not null and p_compte < 0 then raise exception 'Quantité invalide'; end if;
  if not exists (select 1 from public.inventaires where id = p_inventaire and org_id = v_org and statut = 'ouvert') then raise exception 'Inventaire introuvable ou clos'; end if;
  update public.inventaire_lignes set compte = p_compte, note = left(p_note, 200), compte_par_nom = (select nom from public.membres where user_id = auth.uid())
   where inventaire_id = p_inventaire and produit_id = p_produit and org_id = v_org;
  if not found then raise exception 'Produit absent de cet inventaire'; end if;
end $f$;

-- Validation : l'administrateur seul ; tous les produits doivent être comptés ; chaque écart devient un mouvement « inventaire ».
-- L'écart se calcule contre le stock théorique relevé à l'ouverture : les ventes faites pendant le comptage restent valides.
create or replace function public.valider_inventaire(p_inventaire uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); i public.inventaires%rowtype; r record; v_nb int := 0; v_val bigint := 0; v_manque int;
begin
  if not app.has_role('admin') then perform app.deny(); end if;
  select * into i from public.inventaires where id = p_inventaire and org_id = v_org and statut = 'ouvert' for update;
  if not found then raise exception 'Inventaire introuvable ou déjà clos'; end if;
  select count(*) into v_manque from public.inventaire_lignes where inventaire_id = p_inventaire and compte is null;
  if v_manque > 0 then raise exception 'Il reste % produit(s) non compté(s)', v_manque; end if;
  for r in select l.*, p.nom, p.stock, p.cout from public.inventaire_lignes l join public.produits p on p.id = l.produit_id
            where l.inventaire_id = p_inventaire and l.compte <> l.theorique for update of p loop
    if r.stock + (r.compte - r.theorique) < 0 then raise exception 'Écart impossible pour « % » : le stock deviendrait négatif (ventes survenues depuis l''ouverture)', r.nom; end if;
    perform app.stock_mvt(v_org, r.produit_id, r.compte - r.theorique, 'inventaire', i.numero);
    v_nb := v_nb + 1; v_val := v_val + (r.compte - r.theorique)::bigint * r.cout;
  end loop;
  update public.inventaires set statut = 'valide', clos_le = now(), clos_par_nom = (select nom from public.membres where user_id = auth.uid()) where id = p_inventaire;
  perform app.log(v_org, 'Inventaire validé', i.numero || ' — ' || v_nb || ' écart(s)');
  return jsonb_build_object('numero', i.numero, 'ecarts', v_nb, 'valeur_ecart', v_val);
end $f$;

create or replace function public.annuler_inventaire(p_inventaire uuid, p_motif text) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_num text;
begin
  if not app.has_role('admin') then perform app.deny(); end if;
  if coalesce(btrim(p_motif), '') = '' then raise exception 'Motif obligatoire'; end if;
  update public.inventaires set statut = 'annule', clos_le = now(), motif_annulation = left(btrim(p_motif), 300),
         clos_par_nom = (select nom from public.membres where user_id = auth.uid())
   where id = p_inventaire and org_id = v_org and statut = 'ouvert' returning numero into v_num;
  if v_num is null then raise exception 'Inventaire introuvable ou déjà clos'; end if;
  perform app.log(v_org, 'Inventaire annulé', v_num || ' — ' || left(btrim(p_motif), 100));
end $f$;

-- ---------------------------------------------------------------------
-- Journal des mouvements (avec stock après chaque mouvement) et état périodique
-- ---------------------------------------------------------------------
create or replace function public.journal_stock(p_du date, p_au date, p_produit uuid default null, p_type text default null, p_limite int default 2000)
returns table (id bigint, ts timestamptz, produit_id uuid, code text, nom text, type text, qte int, solde int, ref text, par_nom text)
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur') then perform app.deny(); end if;
  return query
    with m as (
      select s.id, s.ts, s.produit_id, s.type, s.qte, s.ref, s.par_nom,
             p.stock - coalesce(sum(s.qte) over (partition by s.produit_id order by s.id desc rows between unbounded preceding and 1 preceding), 0) as solde
        from public.stock_mouvements s join public.produits p on p.id = s.produit_id where s.org_id = app.org())
    select m.id, m.ts, m.produit_id, p.code, p.nom, m.type, m.qte, m.solde::int, m.ref, m.par_nom
      from m join public.produits p on p.id = m.produit_id
     where m.ts >= p_du and m.ts < p_au + 1 and (p_produit is null or m.produit_id = p_produit) and (p_type is null or m.type = p_type)
     order by m.id desc limit least(coalesce(p_limite, 2000), 10000);
end $f$;

create or replace function public.etat_stock(p_du date, p_au date)
returns table (produit_id uuid, code text, nom text, cout int, prix int, ouverture int, entrees int, sorties int, retours int, ajustements int, inventaires int, cloture int)
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'direction', 'superviseur', 'commercial', 'preparateur', 'caissier') then perform app.deny(); end if;
  if p_au < p_du then raise exception 'Période invalide'; end if;
  return query
    select p.id, p.code, p.nom, p.cout, p.prix,
      (p.stock - coalesce(sum(s.qte) filter (where s.ts >= p_du), 0))::int,
      coalesce(sum(s.qte) filter (where s.ts >= p_du and s.ts < p_au + 1 and s.type in ('entree', 'stock_initial')), 0)::int,
      coalesce(sum(s.qte) filter (where s.ts >= p_du and s.ts < p_au + 1 and s.type = 'sortie_commande'), 0)::int,
      coalesce(sum(s.qte) filter (where s.ts >= p_du and s.ts < p_au + 1 and s.type in ('annulation', 'retour_stock')), 0)::int,
      coalesce(sum(s.qte) filter (where s.ts >= p_du and s.ts < p_au + 1 and s.type = 'ajustement'), 0)::int,
      coalesce(sum(s.qte) filter (where s.ts >= p_du and s.ts < p_au + 1 and s.type = 'inventaire'), 0)::int,
      (p.stock - coalesce(sum(s.qte) filter (where s.ts >= p_au + 1), 0))::int
    from public.produits p left join public.stock_mouvements s on s.produit_id = p.id
    where p.org_id = app.org() group by p.id order by p.code;
end $f$;

revoke all on function public.recevoir_stock(uuid, int, text, int), public.ouvrir_inventaire(text), public.saisir_comptage(uuid, uuid, int, text),
  public.valider_inventaire(uuid), public.annuler_inventaire(uuid, text), public.journal_stock(date, date, uuid, text, int), public.etat_stock(date, date) from public, anon;
grant execute on function public.recevoir_stock(uuid, int, text, int), public.ouvrir_inventaire(text), public.saisir_comptage(uuid, uuid, int, text),
  public.valider_inventaire(uuid), public.annuler_inventaire(uuid, text), public.journal_stock(date, date, uuid, text, int), public.etat_stock(date, date) to authenticated;
