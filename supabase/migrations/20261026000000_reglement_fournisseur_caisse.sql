-- Règlement des fournisseurs (vendeurs partenaires) à la caisse : un paiement en espèces ne peut sortir que d'une caisse ouverte
-- dont le solde le couvre. Les sociétés qui n'utilisent pas encore le module Caisse (aucune caisse créée) ne sont pas concernées.

create or replace function app.caisse_especes_ok(p_org uuid, p_montant int) returns text
language plpgsql stable security definer set search_path = '' as $f$
declare v_s uuid; v_solde bigint;
begin
  if not exists (select 1 from public.caisses where org_id = p_org and actif) then return null; end if;
  select s.id into v_s from public.caisses c join public.caisse_sessions s on s.caisse_id = c.id and s.statut = 'ouverte'
   where c.org_id = p_org and c.actif order by c.compte, c.cree_le limit 1;
  if v_s is null then return 'Aucune caisse ouverte : ouvrez la caisse avant de payer en espèces'; end if;
  v_solde := app.caisse_solde_session(v_s);
  if p_montant > v_solde then return 'Solde de caisse insuffisant (' || v_solde || ' F disponibles)'; end if;
  return null;
end $f$;
revoke all on function app.caisse_especes_ok(uuid, int) from public, anon, authenticated;

create or replace function public.regler_vendeur(p_vid uuid, p_montant int, p_mode text, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_rest bigint; v_err text;
begin
  if not app.has_role('admin', 'caissier') then perform app.deny(); end if;
  perform 1 from public.vendeurs where id = p_vid and org_id = v_org for update;
  if not found then raise exception 'Vendeur introuvable'; end if;
  select restant into v_rest from public.vendeur_dues(p_vid);
  if p_montant is null or p_montant <= 0 or p_montant > v_rest then raise exception 'Montant invalide (reste à régler : % F)', v_rest; end if;
  if p_mode ~* '^esp' then
    v_err := app.caisse_especes_ok(v_org, p_montant);
    if v_err is not null then raise exception '%', v_err; end if;
  end if;
  insert into public.reglements_vendeurs(org_id, vendeur_id, montant, mode, note, par, par_nom)
  values (v_org, p_vid, p_montant, p_mode, p_note, auth.uid(), (select nom from public.membres where user_id = auth.uid()));
  perform app.log(v_org, 'Règlement vendeur', (select nom from public.vendeurs where id = p_vid) || ' — ' || p_montant || ' F');
end $f$;
