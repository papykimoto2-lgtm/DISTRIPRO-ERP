-- Suivi client en direct (lien personnel par commande) et avis sur la livraison.
-- Le client n'a pas de compte : le lien contient un secret de 256 bits ; la page ne révèle ni le code de livraison,
-- ni le téléphone du livreur, ni les notes internes. La position du livreur n'est donnée que pendant la course.

create table public.suivi_liens (
  token text primary key default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid not null unique references public.commandes(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '30 days'
);
alter table public.suivi_liens enable row level security;     -- aucune politique : accès uniquement par les fonctions ci-dessous

create table public.avis_livraison (
  livraison_id uuid primary key references public.livraisons(id) on delete cascade,
  org_id uuid not null references public.organisations(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id) on delete cascade,
  note smallint not null check (note between 1 and 5),
  commentaire text check (char_length(commentaire) <= 300),
  cree_le timestamptz not null default now()
);
create index on public.avis_livraison (org_id, livreur_id);
alter table public.avis_livraison enable row level security;
create policy avis_select on public.avis_livraison for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur', 'direction')) or livreur_id = (select app.livreur_id())));
grant select on public.avis_livraison to authenticated;
create trigger avis_ajout_seul before update or delete on public.avis_livraison for each row execute function app.trg_append_only();

create or replace function public.creer_lien_suivi(p_commande uuid) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); c public.commandes%rowtype; v_token text;
begin
  select * into c from public.commandes where id = p_commande and org_id = v_org;
  if not found then raise exception 'Commande introuvable'; end if;
  if not (app.has_role('admin', 'superviseur', 'commercial') or coalesce(app.role() = 'vendeur' and c.vendeur_id = app.vendeur_id(), false)) then perform app.deny(); end if;
  insert into public.suivi_liens(org_id, commande_id) values (v_org, p_commande)
    on conflict (commande_id) do update set expires_at = greatest(public.suivi_liens.expires_at, now() + interval '30 days')
    returning token into v_token;
  return v_token;
end $f$;

create or replace function public.suivi_get(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare l public.suivi_liens%rowtype; c public.commandes%rowtype; lv public.livraisons%rowtype; o public.organisations%rowtype;
        v_liv text; v_eta timestamptz; v_pos jsonb; v_dest jsonb; v_hist jsonb; v_avis jsonb; v_delai int;
begin
  select * into l from public.suivi_liens where token = p_token and expires_at > now();
  if not found then return null; end if;
  select * into c from public.commandes where id = l.commande_id;
  select * into o from public.organisations where id = c.org_id;
  select * into lv from public.livraisons where commande_id = c.id order by tentative desc limit 1;
  if lv.id is not null and lv.statut in ('affectee','acceptee','en_cours','livree') then
    select split_part(nom, ' ', 1) into v_liv from public.livreurs where id = lv.livreur_id;
  end if;
  if lv.statut = 'en_cours' then
    select coalesce((select delai_min from public.zones z where z.org_id = c.org_id and z.nom = c.adr ->> 'zone'), 60) into v_delai;
    v_eta := coalesce(lv.depart_at, now()) + make_interval(mins => v_delai);
    select jsonb_build_object('lat', p.lat, 'lng', p.lng, 'ts', p.ts) into v_pos
      from public.positions_gps p where p.livraison_id = lv.id and p.ts > now() - interval '15 minutes' order by p.ts desc limit 1;
  end if;
  select case when a.lat is null then null else jsonb_build_object('lat', a.lat, 'lng', a.lng) end into v_dest from public.adresses a where a.id = c.adresse_id;
  select coalesce(jsonb_agg(jsonb_build_object('a', h.a, 'ts', h.ts) order by h.id), '[]'::jsonb) into v_hist from public.commande_historique h where h.commande_id = c.id;
  select jsonb_build_object('note', a.note, 'commentaire', a.commentaire) into v_avis from public.avis_livraison a where a.livraison_id = lv.id;
  return jsonb_build_object('org', o.nom, 'w', o.whatsapp, 'numero', c.numero, 'statut', c.statut,
    'lieu', concat_ws(' · ', c.adr ->> 'zone', c.adr ->> 'quartier'), 'livreur', v_liv, 'eta', v_eta, 'pos', v_pos, 'dest', v_dest,
    'hist', v_hist, 'avis', v_avis, 'peut_noter', (c.statut = 'livree' and lv.statut = 'livree' and v_avis is null),
    'a_payer', case when lv.statut in ('affectee','acceptee','en_cours') then lv.montant_attendu end);
end $f$;

create or replace function public.suivi_noter(p_token text, p_note int, p_commentaire text default null) returns boolean
language plpgsql security definer set search_path = '' as $f$
declare l public.suivi_liens%rowtype; c public.commandes%rowtype; lv public.livraisons%rowtype;
begin
  if p_note is null or p_note not between 1 and 5 then raise exception 'Note invalide'; end if;
  select * into l from public.suivi_liens where token = p_token and expires_at > now();
  if not found then return false; end if;
  select * into c from public.commandes where id = l.commande_id;
  select * into lv from public.livraisons where commande_id = c.id and statut = 'livree' order by tentative desc limit 1;
  if c.statut <> 'livree' or lv.id is null then return false; end if;
  insert into public.avis_livraison(livraison_id, org_id, livreur_id, note, commentaire)
    values (lv.id, c.org_id, lv.livreur_id, p_note, nullif(left(btrim(coalesce(p_commentaire, '')), 300), '')) on conflict do nothing;
  if not found then return false; end if;
  perform app.log(c.org_id, 'Avis client', c.numero || ' · ' || p_note || '/5');
  return true;
end $f$;

revoke all on function public.creer_lien_suivi(uuid), public.suivi_get(text), public.suivi_noter(text, int, text) from public, anon;
grant execute on function public.creer_lien_suivi(uuid) to authenticated;
grant execute on function public.suivi_get(text), public.suivi_noter(text, int, text) to anon, authenticated;
