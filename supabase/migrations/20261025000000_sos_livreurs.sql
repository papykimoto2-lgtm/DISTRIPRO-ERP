-- Alertes SOS des livreurs : le livreur déclenche une alerte (accident, agression, panne, malaise…) avec sa position ;
-- l'administrateur et les superviseurs la voient immédiatement, la prennent en charge puis la clôturent. Rien ne se supprime.

create table public.alertes_sos (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  livreur_id uuid not null references public.livreurs(id) on delete cascade,
  type text not null check (type in ('accident', 'agression', 'panne', 'malaise', 'autre')),
  note text check (char_length(note) <= 300),
  lat numeric(9,6) check (lat between -90 and 90),
  lng numeric(9,6) check (lng between -180 and 180),
  acc int,
  statut text not null default 'ouverte' check (statut in ('ouverte', 'prise', 'cloturee', 'fausse')),
  cree_le timestamptz not null default now(),
  prise_par_nom text,
  prise_le timestamptz,
  cloturee_par_nom text,
  cloturee_le timestamptz,
  resolution text check (char_length(resolution) <= 300)
);
create index on public.alertes_sos (org_id, statut, cree_le desc);
create unique index sos_une_ouverte_par_livreur on public.alertes_sos (livreur_id) where statut in ('ouverte', 'prise');
alter table public.alertes_sos enable row level security;
create policy sos_select on public.alertes_sos for select to authenticated using (org_id = (select app.org()) and (
  (select app.has_role('admin', 'superviseur', 'direction')) or livreur_id = (select app.livreur_id())));
grant select on public.alertes_sos to authenticated;      -- écriture uniquement par les fonctions

create or replace function public.sos_declencher(p_type text, p_note text default null, p_lat numeric default null, p_lng numeric default null, p_acc int default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); v_lv uuid := app.livreur_id(); v_id uuid; v_lat numeric := p_lat; v_lng numeric := p_lng; v_nom text;
begin
  if v_lv is null then perform app.deny(); end if;
  if p_type not in ('accident', 'agression', 'panne', 'malaise', 'autre') then raise exception 'Type d''alerte invalide'; end if;
  if (select count(*) from public.alertes_sos where livreur_id = v_lv and cree_le > now() - interval '1 hour') >= 5 then raise exception 'Trop d''alertes envoyées : appelez directement votre superviseur'; end if;
  select id into v_id from public.alertes_sos where livreur_id = v_lv and statut in ('ouverte', 'prise');
  if v_id is not null then return jsonb_build_object('id', v_id, 'deja', true); end if;      -- une seule alerte active par livreur
  if v_lat is not null and (v_lat not between -90 and 90 or v_lng is null or v_lng not between -180 and 180) then raise exception 'Position GPS invalide'; end if;
  if v_lat is null then   -- dernière position connue
    select p.lat, p.lng into v_lat, v_lng from public.positions_gps p where p.livreur_id = v_lv and p.ts > now() - interval '30 minutes' order by p.ts desc limit 1;
  end if;
  insert into public.alertes_sos(org_id, livreur_id, type, note, lat, lng, acc) values (v_org, v_lv, p_type, nullif(left(btrim(coalesce(p_note, '')), 300), ''), v_lat, v_lng, p_acc) returning id into v_id;
  select nom into v_nom from public.livreurs where id = v_lv;
  perform app.log(v_org, 'ALERTE SOS', v_nom || ' — ' || p_type);
  return jsonb_build_object('id', v_id, 'deja', false);
end $f$;

-- Prise en charge, clôture ou fausse alerte par l'équipe ; le livreur peut seulement signaler une fausse alerte sur la sienne
create or replace function public.sos_traiter(p_id uuid, p_action text, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_org uuid := app.org(); a public.alertes_sos%rowtype; v_nom text := (select nom from public.membres where user_id = auth.uid());
begin
  select * into a from public.alertes_sos where id = p_id and org_id = v_org for update;
  if not found then raise exception 'Alerte introuvable'; end if;
  if a.statut in ('cloturee', 'fausse') then raise exception 'Alerte déjà traitée'; end if;
  if p_action = 'fausse' and app.livreur_id() is not null and a.livreur_id = app.livreur_id() then
    update public.alertes_sos set statut = 'fausse', cloturee_par_nom = v_nom, cloturee_le = now(), resolution = 'Fausse alerte signalée par le livreur' where id = p_id;
    perform app.log(v_org, 'SOS : fausse alerte', (select nom from public.livreurs where id = a.livreur_id)); return;
  end if;
  if not app.has_role('admin', 'superviseur') then perform app.deny(); end if;
  if p_action = 'prendre' then
    if a.statut <> 'ouverte' then raise exception 'Alerte déjà prise en charge par %', coalesce(a.prise_par_nom, 'un collègue'); end if;
    update public.alertes_sos set statut = 'prise', prise_par_nom = v_nom, prise_le = now() where id = p_id;
  elsif p_action in ('cloturer', 'fausse') then
    if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'Précisez ce qui a été fait'; end if;
    update public.alertes_sos set statut = case when p_action = 'fausse' then 'fausse' else 'cloturee' end, cloturee_par_nom = v_nom, cloturee_le = now(), resolution = left(btrim(p_note), 300) where id = p_id;
  else raise exception 'Action inconnue'; end if;
  perform app.log(v_org, 'SOS : ' || p_action, (select nom from public.livreurs where id = a.livreur_id));
end $f$;

revoke all on function public.sos_declencher(text, text, numeric, numeric, int), public.sos_traiter(uuid, text, text) from public, anon;
grant execute on function public.sos_declencher(text, text, numeric, numeric, int), public.sos_traiter(uuid, text, text) to authenticated;
