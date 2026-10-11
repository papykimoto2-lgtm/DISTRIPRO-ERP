-- =====================================================================
-- Notifications clients : file d'attente + envoi automatique (WhatsApp / SMS)
-- Dépend de 20261010000000_angels_erp_schema.sql
-- Principe : la base prépare le message à chaque étape de la commande ;
-- une Edge Function (service_role) l'envoie chez le prestataire, avec
-- reprises, puis un webhook enregistre « livré » / « lu » / « échec ».
-- Aucun secret du prestataire n'existe côté navigateur ni en base.
-- =====================================================================

-- Consentement du client à recevoir des messages (exigé par WhatsApp)
alter table public.clients add column consent_notifications boolean not null default true;

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations(id) on delete cascade,
  commande_id uuid references public.commandes(id) on delete cascade,
  event text not null check (event in ('confirmee','en_cours','livree','echouee')),
  cle text not null,                                    -- anti-doublon : commande + événement (+ n° de tentative de livraison sauf confirmation)
  canal text not null default 'whatsapp' check (canal in ('whatsapp','sms')),
  tel text not null,
  nom text,
  vars jsonb not null default '{}'::jsonb,              -- variables du modèle (pour les modèles WhatsApp approuvés)
  message text not null,
  statut text not null default 'a_envoyer'
    check (statut in ('a_envoyer','envoi_en_cours','envoye','livre','lu','echec','ignore')),
  tentatives int not null default 0,
  prochaine_tentative timestamptz not null default now(),
  provider text,
  provider_id text,
  erreur text,
  created_at timestamptz not null default now(),
  envoye_at timestamptz,
  maj_at timestamptz,
  par uuid,
  unique (org_id, cle)
);
create index on public.notifications (statut, prochaine_tentative);
create index on public.notifications (provider_id) where provider_id is not null;
create index on public.notifications (org_id, created_at desc);
alter table public.notifications enable row level security;

create policy notif_select on public.notifications for select to authenticated
  using (org_id = (select app.org()) and (select app.has_role('admin', 'superviseur', 'commercial', 'direction')));

-- ---------------------------------------------------------------------
-- Préparation du message (à chaque changement de statut utile)
-- ---------------------------------------------------------------------
create or replace function app.enfiler_notification(p_cid uuid, p_event text, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $f$
declare
  c public.commandes%rowtype; o public.organisations%rowtype; cl public.clients%rowtype; l public.livraisons%rowtype;
  v_tpl text; v_msg text; v_vars jsonb; v_delai int; v_code text; v_k text; v_v text; v_canal text;
  v_tel text; v_solde int;
begin
  if coalesce(current_setting('app.force', true), '') = '1' then return; end if;     -- correction exceptionnelle : pas de message
  select * into c from public.commandes where id = p_cid;
  if not found then return; end if;
  select * into o from public.organisations where id = c.org_id;
  if coalesce(o.config->'notif'->>p_event, 'true') <> 'true' then return; end if;
  select * into cl from public.clients where id = c.client_id;
  if not cl.consent_notifications then return; end if;
  v_tel := btrim(coalesce(cl.tel, ''));
  if v_tel = '' then return; end if;

  select * into l from public.livraisons where commande_id = p_cid order by affectee_at desc limit 1;
  if l.id is not null then select code into v_code from public.livraison_codes where livraison_id = l.id; end if;
  select delai_min into v_delai from public.zones where org_id = c.org_id and nom = c.adr->>'zone';
  v_solde := app.solde_commande(p_cid);

  v_tpl := coalesce(nullif(o.config->'tpl'->>p_event, ''), case p_event
    when 'confirmee' then 'Bonjour {client}, votre commande {numero} est confirmée. Reste à régler à la livraison : {solde}. — {org}'
    when 'en_cours'  then '{client}, votre livreur {livreur} est parti avec votre commande {numero}. Arrivée estimée vers {heure}. Code à donner à la réception : {code}. — {org}'
    when 'livree'    then 'Merci {client} ! Votre commande {numero} a été livrée. — {org}'
    when 'echouee'   then '{client}, nous n''avons pas pu vous livrer la commande {numero} ({motif}). Nous vous recontactons pour une nouvelle tentative. — {org}' end);

  v_vars := jsonb_build_object(
    'client', cl.nom, 'numero', c.numero, 'org', o.nom,
    'livreur', coalesce(split_part((select nom from public.livreurs where id = l.livreur_id), ' ', 1), ''),
    'heure', to_char((now() + make_interval(mins => coalesce(v_delai, 45))) at time zone 'Africa/Abidjan', 'HH24:MI'),
    'code', coalesce(v_code, ''),
    'solde', replace(trim(to_char(v_solde, 'FM999,999,999')), ',', ' ') || ' F',
    'motif', regexp_replace(coalesce(p_note, ''), '^Échec : ', ''));
  v_msg := v_tpl;
  for v_k, v_v in select key, value from jsonb_each_text(v_vars) loop
    v_msg := replace(v_msg, '{' || v_k || '}', v_v);
  end loop;
  v_canal := coalesce(nullif(o.config->'messagerie'->>'canal', ''), 'whatsapp');
  if v_canal not in ('whatsapp', 'sms') then v_canal := 'whatsapp'; end if;

  insert into public.notifications(org_id, commande_id, event, cle, canal, tel, nom, vars, message)
  values (c.org_id, p_cid, p_event,
          p_cid::text || ':' || p_event || case when p_event = 'confirmee' then ''
                                                else ':' || (select count(*) from public.livraisons where commande_id = p_cid) end,
          v_canal, v_tel, cl.nom, v_vars, v_msg)
  on conflict (org_id, cle) do nothing;
end $f$;

create or replace function app.trg_notif_statut() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  perform app.enfiler_notification(new.id, new.statut, coalesce(current_setting('app.note', true), ''));
  return new;
end $f$;
create trigger notif_statut after update of statut on public.commandes
  for each row when (old.statut is distinct from new.statut and new.statut in ('confirmee', 'en_cours', 'livree', 'echouee'))
  execute function app.trg_notif_statut();

-- ---------------------------------------------------------------------
-- Actions du personnel (mode manuel ou correction)
-- ---------------------------------------------------------------------
create or replace function public.notification_ignorer(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'superviseur', 'commercial') then perform app.deny(); end if;
  update public.notifications set statut = 'ignore', par = auth.uid(), maj_at = now()
   where id = p_id and org_id = app.org() and statut in ('a_envoyer', 'echec');
  if not found then raise exception 'Message introuvable ou déjà traité'; end if;
end $f$;

create or replace function public.notification_modifier(p_id uuid, p_message text) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'superviseur', 'commercial') then perform app.deny(); end if;
  if coalesce(btrim(p_message), '') = '' then raise exception 'Message vide'; end if;
  update public.notifications set message = left(p_message, 1000), maj_at = now()
   where id = p_id and org_id = app.org() and statut = 'a_envoyer';
  if not found then raise exception 'Seul un message en attente peut être modifié'; end if;
end $f$;

create or replace function public.notification_renvoyer(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'superviseur', 'commercial') then perform app.deny(); end if;
  update public.notifications set statut = 'a_envoyer', tentatives = 0, prochaine_tentative = now(), erreur = null, maj_at = now()
   where id = p_id and org_id = app.org() and statut = 'echec';
  if not found then raise exception 'Seul un envoi en échec peut être relancé'; end if;
end $f$;

create or replace function public.notification_marquer_manuel(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if not app.has_role('admin', 'superviseur', 'commercial') then perform app.deny(); end if;
  update public.notifications set statut = 'envoye', provider = 'manuel', envoye_at = now(), maj_at = now(), par = auth.uid()
   where id = p_id and org_id = app.org() and statut = 'a_envoyer';
  if not found then raise exception 'Message introuvable ou déjà traité'; end if;
end $f$;

-- ---------------------------------------------------------------------
-- Fonctions réservées à l'Edge Function (service_role uniquement)
-- ---------------------------------------------------------------------
-- Réserve un lot de messages à envoyer : un message n'est donné qu'à UN seul appelant (SKIP LOCKED).
create or replace function public.reserver_notifications(p_limit int default 20) returns setof public.notifications
language plpgsql security definer set search_path = '' as $f$
begin
  return query
  with pick as (
    select n.id from public.notifications n join public.organisations o on o.id = n.org_id
     where n.statut = 'a_envoyer' and n.prochaine_tentative <= now()
       and coalesce(o.config->'messagerie'->>'auto', 'false') = 'true'
     order by n.created_at limit greatest(1, least(p_limit, 100))
       for update of n skip locked)
  update public.notifications n set statut = 'envoi_en_cours', maj_at = now()
    from pick where n.id = pick.id
  returning n.*;
end $f$;

-- Résultat d'un envoi : succès, échec à retenter (3 essais, attente 2^n minutes) ou échec définitif.
create or replace function public.marquer_notification(p_id uuid, p_ok boolean, p_provider text, p_provider_id text, p_erreur text, p_definitif boolean default false) returns void
language plpgsql security definer set search_path = '' as $f$
declare n public.notifications%rowtype;
begin
  select * into n from public.notifications where id = p_id for update;
  if not found or n.statut <> 'envoi_en_cours' then return; end if;
  if p_ok then
    update public.notifications set statut = 'envoye', provider = p_provider, provider_id = p_provider_id, erreur = null,
           tentatives = n.tentatives + 1, envoye_at = now(), maj_at = now() where id = p_id;
  elsif p_definitif or n.tentatives + 1 >= 3 then
    update public.notifications set statut = 'echec', provider = p_provider, erreur = left(p_erreur, 500),
           tentatives = n.tentatives + 1, maj_at = now() where id = p_id;
  else
    update public.notifications set statut = 'a_envoyer', provider = p_provider, erreur = left(p_erreur, 500),
           tentatives = n.tentatives + 1, prochaine_tentative = now() + make_interval(mins => power(2, n.tentatives + 1)::int), maj_at = now()
     where id = p_id;
  end if;
end $f$;

-- Accusé du prestataire : le statut ne fait qu'avancer (envoyé -> livré -> lu) ; « échec » est possible tant que rien n'est livré.
create or replace function public.maj_statut_provider(p_provider_id text, p_statut text, p_erreur text default null) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if p_statut not in ('livre', 'lu', 'echec') then raise exception 'Statut inconnu'; end if;
  update public.notifications n set
      statut = p_statut, maj_at = now(), erreur = case when p_statut = 'echec' then left(p_erreur, 500) else n.erreur end
   where n.provider_id = p_provider_id
     and ((p_statut = 'livre' and n.statut = 'envoye')
       or (p_statut = 'lu' and n.statut in ('envoye', 'livre'))
       or (p_statut = 'echec' and n.statut in ('envoye', 'envoi_en_cours')));
end $f$;

-- ---------------------------------------------------------------------
-- Privilèges
-- ---------------------------------------------------------------------
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
grant update (consent_notifications) on public.clients to authenticated;
do $f$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('app', 'public') and p.proname in ('enfiler_notification', 'trg_notif_statut', 'notification_ignorer',
             'notification_modifier', 'notification_renvoyer', 'notification_marquer_manuel', 'reserver_notifications',
             'marquer_notification', 'maj_statut_provider') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $f$;
grant execute on function app.enfiler_notification(uuid, text, text), app.trg_notif_statut() to authenticated;
grant execute on function public.notification_ignorer(uuid), public.notification_modifier(uuid, text),
  public.notification_renvoyer(uuid), public.notification_marquer_manuel(uuid) to authenticated;
grant execute on function public.reserver_notifications(int), public.marquer_notification(uuid, boolean, text, text, text, boolean),
  public.maj_statut_provider(text, text, text) to service_role;
