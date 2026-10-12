-- Paiement du client final chez le fournisseur et/ou chez le livreur désigné par ANGEL'S GROUP.
-- `paye_vendeur` : part des articles déjà payée directement au fournisseur. Le livreur n'encaisse que le reste (articles restants + livraison),
-- et le fournisseur est réglé par ANGEL'S GROUP sur la part encaissée par ANGEL'S GROUP seulement (moins la commission).
-- Un paiement intégral chez le fournisseur ne génère donc ni règlement ni commission (comportement d'avant).

alter table public.commandes add column paye_vendeur int not null default 0 check (paye_vendeur >= 0);
update public.commandes set paye_vendeur = montant_produits - remise where vendeur_encaisse and paye_vendeur = 0;

create or replace function public.vendeur_deposer_commande(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_org uuid := app.org(); v_vend uuid := app.vendeur_id(); v_cl uuid; v_ad uuid; v_z record;
  v_tel text := regexp_replace(coalesce(p#>>'{client,tel}', ''), '\s', '', 'g'); v_lignes jsonb; v_prods int;
  v_pv int; v_id uuid; v_num text;
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
    insert into public.adresses(org_id, client_id, libelle, zone, quartier, repere, instructions, defaut)
    values (v_org, v_cl, 'Livraison', v_z.nom, btrim(coalesce(p#>>'{adresse,quartier}', '')), btrim(coalesce(p#>>'{adresse,repere}', '')),
            btrim(coalesce(p#>>'{adresse,instructions}', '')), not exists (select 1 from public.adresses where client_id = v_cl))
    returning id into v_ad;
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

-- Montant dû aux vendeurs (part encaissée par ANGEL'S GROUP, moins commission)
create or replace function public.vendeur_dues(p_vid uuid default null) returns table (vendeur_id uuid, acquis bigint, regle bigint, restant bigint, attente bigint)
language plpgsql stable security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_target uuid := p_vid;
begin
  if app.role() = 'vendeur' then v_target := app.vendeur_id();
  elsif not app.has_role('admin', 'direction', 'caissier', 'commercial', 'superviseur') then perform app.deny(); end if;
  return query
    select v.id,
      coalesce(sum(round((c.montant_produits - c.remise - c.paye_vendeur) * (1 - v.commission_pct / 100)))
        filter (where c.statut = 'livree' and (c.montant_produits - c.remise - c.paye_vendeur) > 0 and app.solde_commande(c.id) = 0), 0)::bigint as a,
      (select coalesce(sum(r.montant), 0) from public.reglements_vendeurs r where r.vendeur_id = v.id)::bigint as g,
      (coalesce(sum(round((c.montant_produits - c.remise - c.paye_vendeur) * (1 - v.commission_pct / 100)))
        filter (where c.statut = 'livree' and (c.montant_produits - c.remise - c.paye_vendeur) > 0 and app.solde_commande(c.id) = 0), 0)
       - (select coalesce(sum(r.montant), 0) from public.reglements_vendeurs r where r.vendeur_id = v.id))::bigint as rest,
      coalesce(sum(round((c.montant_produits - c.remise - c.paye_vendeur) * (1 - v.commission_pct / 100)))
        filter (where c.statut in ('confirmee','preparation','prete','affectee','en_cours') and (c.montant_produits - c.remise - c.paye_vendeur) > 0), 0)::bigint as att
    from public.vendeurs v left join public.commandes c on c.vendeur_id = v.id
    where v.org_id = v_org and (v_target is null or v.id = v_target)
    group by v.id, v.commission_pct;
end $f$;

-- Commandes qui composent le montant dû à un vendeur
create or replace function public.vendeur_eligibles(p_vid uuid default null) returns table (vendeur_id uuid, commande_id uuid, numero text, net bigint, livree_le timestamptz)
language plpgsql stable security definer set search_path = '' as $f$
declare v_target uuid := p_vid;
begin
  if app.role() = 'vendeur' then v_target := app.vendeur_id();
  elsif not app.has_role('admin', 'direction', 'caissier', 'commercial', 'superviseur') then perform app.deny(); end if;
  return query
    select v.id, c.id, c.numero, round((c.montant_produits - c.remise - c.paye_vendeur) * (1 - v.commission_pct / 100))::bigint,
           (select max(l.fin_at) from public.livraisons l where l.commande_id = c.id and l.statut = 'livree')
    from public.vendeurs v join public.commandes c on c.vendeur_id = v.id
    where v.org_id = app.org() and (v_target is null or v.id = v_target)
      and c.statut = 'livree' and (c.montant_produits - c.remise - c.paye_vendeur) > 0 and app.solde_commande(c.id) = 0
    order by 5 desc;
end $f$;
