-- Livreurs externes : ANGEL'S GROUP prélève une commission sur les frais de livraison.
-- Le livreur externe (partenaire, avec sa propre moto) garde sa part des frais sur l'argent qu'il encaisse : il ne reverse que
-- l'encaissement moins sa part ; ANGEL'S GROUP garde la commission. La part est figée à la livraison (changer le taux plus tard
-- ne modifie pas les courses passées). Si le livreur n'a pas détenu assez d'argent pour retenir sa part (client payé directement
-- sur le compte d'ANGEL'S GROUP), le reste lui est dû et se règle par la paie habituelle.

alter table public.livreurs add column type text not null default 'interne' check (type in ('interne', 'externe'));
alter table public.livreurs add column commission_pct numeric(5,2) not null default 0 check (commission_pct between 0 and 100);   -- % des frais prélevé par ANGEL'S GROUP (externes)
alter table public.livraisons add column part_livreur int check (part_livreur >= 0);          -- externes : frais - commission, figé à la livraison
alter table public.livraisons add column commission_angels int check (commission_angels >= 0);

create or replace function app.trg_part_livreur() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_frais int; v_pct numeric; v_type text;
begin
  if new.statut = 'livree' and old.statut is distinct from 'livree' then
    select l.type, l.commission_pct into v_type, v_pct from public.livreurs l where l.id = new.livreur_id;
    if v_type = 'externe' then
      select c.frais into v_frais from public.commandes c where c.id = new.commande_id;
      new.commission_angels := round(coalesce(v_frais, 0) * coalesce(v_pct, 0) / 100)::int;
      new.part_livreur := greatest(coalesce(v_frais, 0) - new.commission_angels, 0);
    end if;
  end if;
  return new;
end $f$;
create trigger livraisons_part_livreur before update of statut on public.livraisons for each row execute function app.trg_part_livreur();

-- Part déjà retenue par le livreur : au plus ce qu'il a réellement détenu sur la course (hors paiement direct sur le compte d'ANGEL'S GROUP)
create or replace function app.retenu_livreur(p_lid uuid) returns bigint
language sql stable security definer set search_path = '' as $f$
  select coalesce(sum(least(l.part_livreur, coalesce((select sum(f.montant) from public.fonds f
           where f.livraison_id = l.id and f.type = 'encaissement' and not f.direct), 0))), 0)::bigint
  from public.livraisons l where l.livreur_id = p_lid and l.statut = 'livree' and l.part_livreur is not null
$f$;

create or replace function app.solde_livreur(p_lid uuid) returns bigint
language sql stable security definer set search_path = '' as $f$
  select (coalesce(sum(case when type = 'encaissement' and not direct then montant when type = 'reversement' then -montant end), 0)
          - app.retenu_livreur(p_lid))::bigint
  from public.fonds where livreur_id = p_lid
$f$;
revoke all on function app.trg_part_livreur(), app.retenu_livreur(uuid), app.solde_livreur(uuid) from public, anon, authenticated;

drop function public.solde_livreurs();
create or replace function public.solde_livreurs() returns table (livreur_id uuid, encaisse bigint, reverse bigint, retenu bigint, solde bigint)
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (app.has_role('admin', 'direction', 'caissier', 'superviseur') or app.livreur_id() is not null) then perform app.deny(); end if;
  return query
    select l.id, coalesce(sum(f.montant) filter (where f.type = 'encaissement' and not f.direct), 0)::bigint,
           coalesce(sum(f.montant) filter (where f.type = 'reversement'), 0)::bigint,
           app.retenu_livreur(l.id),
           app.solde_livreur(l.id)
    from public.livreurs l left join public.fonds f on f.livreur_id = l.id
    where l.org_id = app.org() and (app.livreur_id() is null or l.id = app.livreur_id())
    group by l.id;
end $f$;
revoke all on function public.solde_livreurs() from public, anon;
grant execute on function public.solde_livreurs() to authenticated;

-- Reversement, déclaration et validation d'un versement : le restant tient compte de la part retenue
create or replace function public.reversement(p_lid uuid, p_montant int, p_mode text, p_note text default '', p_ref text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_solde bigint; v_r text := nullif(upper(btrim(coalesce(p_ref, ''))), '');
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  perform 1 from public.livreurs where id = p_lid and org_id = v_org for update;
  if not found then raise exception 'Livreur introuvable'; end if;
  v_solde := app.solde_livreur(p_lid);
  if p_montant is null or p_montant <= 0 or p_montant > v_solde then raise exception 'Montant invalide (restant à reverser : % F)', v_solde; end if;
  if app.est_mobile(p_mode) then
    if v_r is null or length(v_r) < 4 then raise exception 'Référence de la transaction Mobile Money obligatoire'; end if;
  else v_r := null; end if;
  if v_r is not null and exists (select 1 from public.fonds where org_id = v_org and upper(btrim(ref)) = v_r) then raise exception 'Cette référence de transaction est déjà enregistrée'; end if;
  insert into public.fonds(org_id, type, livreur_id, montant, mode, ref, note, par, par_nom)
  values (v_org, 'reversement', p_lid, p_montant, p_mode, v_r, p_note, auth.uid(), (select nom from public.membres where user_id = auth.uid()));
  perform app.log(v_org, 'Reversement validé', (select nom from public.livreurs where id = p_lid) || ' — ' || p_montant || ' F (reste ' || (v_solde - p_montant) || ' F)');
end $f$;
create or replace function public.declarer_versement(p_montant int, p_mode text, p_ref text, p_note text default null) returns uuid
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_me uuid := app.livreur_id(); v_solde bigint; v_att bigint; v_r text := nullif(upper(btrim(coalesce(p_ref, ''))), ''); v_id uuid;
begin
  if v_me is null then perform app.deny(); end if;
  if not app.est_mobile(p_mode) then raise exception 'Seul un virement Mobile Money se déclare ; le comptant est remis au caissier'; end if;
  if v_r is null or length(v_r) < 4 then raise exception 'Référence de la transaction obligatoire (identifiant reçu par SMS)'; end if;
  if exists (select 1 from public.fonds where org_id = v_org and upper(btrim(ref)) = v_r)
     or exists (select 1 from public.versements_declares where org_id = v_org and upper(btrim(ref)) = v_r and statut <> 'rejete') then raise exception 'Cette référence de transaction est déjà enregistrée'; end if;
  v_solde := app.solde_livreur(v_me);
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
    v_solde := app.solde_livreur(d.livreur_id);
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
