-- Tests des zones du Grand Abidjan et de la position GPS du fournisseur. Prérequis : stub + les 22 migrations, base neuve.
\set ON_ERROR_STOP on
create or replace function t_as(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u::text,false); execute 'set role authenticated'; end $$;
create or replace function t_anon() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',false); execute 'set role anon'; end $$;
create or replace function t_root() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub','',false); end $$;
create or replace function t_ok(c boolean, label text) returns void language plpgsql as $$ begin if c then raise notice 'PASS  %',label; else raise warning 'FAIL  %',label; end if; end $$;
create or replace function t_fail(u uuid, q text, frag text, label text) returns void language plpgsql as $$
declare m text; begin if u is null then perform t_anon(); else perform t_as(u); end if;
  begin execute q; perform t_root(); raise warning 'FAIL  % (aucune erreur)',label;
  exception when others then get stacked diagnostics m = message_text; perform t_root();
    if m ~* frag then raise notice 'PASS  % [%]',label,left(m,70); else raise warning 'FAIL  % (message: %)',label,m; end if; end; end $$;
create or replace function t_j(u uuid, q text) returns jsonb language plpgsql as $$ declare r jsonb; begin if u is null then perform t_anon(); else perform t_as(u); end if; execute q into r; perform t_root(); return r; end $$;
grant execute on function t_as(uuid), t_anon(), t_root(), t_ok(boolean,text), t_fail(uuid,text,text,text), t_j(uuid,text) to public;
create or replace function t_n(u uuid, q text) returns bigint language plpgsql as $$ declare r bigint; begin if u is null then perform t_anon(); else perform t_as(u); end if; execute q into r; perform t_root(); return r; end $$;
grant execute on function t_n(uuid,text) to public;
create temp table ids(k text primary key, v uuid);
insert into ids select k, gen_random_uuid() from unnest(array['A','S','V1','V2','L1','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',10),('00000000-0000-0000-0000-0000000000b2',:'org1','Concurrent',0);
insert into public.membres(user_id,org_id,role,nom,vendeur_id) values (u('S'),:'org1','superviseur','Awa',null),
 (u('V1'),:'org1','vendeur','Aya','00000000-0000-0000-0000-0000000000b1'),(u('V2'),:'org1','vendeur','Concurrent','00000000-0000-0000-0000-0000000000b2');
-- 1. Zones
select t_ok((select count(*) from public.zones where org_id=:'org1')=22, 'une nouvelle société reçoit les 22 zones (Grand Abidjan et périphérie)');
select t_ok((select count(*) from public.zones where org_id=:'org1' and nom in ('Songon','Grand-Bassam','Dabou','Bingerville','Anyama','Adjamé','Attécoubé','Jacqueville'))=8, 'Songon, Grand-Bassam, Dabou, Bingerville, Anyama, Adjamé, Attécoubé, Jacqueville présentes');
select t_ok((select frais from public.zones where org_id=:'org1' and nom='Cocody')=1500, 'les zones historiques gardent leurs tarifs');
update public.zones set frais=2500 where org_id=:'org1' and nom='Dabou';
delete from public.zones where org_id=:'org1' and nom='Assinie';
select app.zones_defaut(:'org1');
select t_ok((select frais from public.zones where org_id=:'org1' and nom='Dabou')=2500, 'rejouer l''ajout ne remplace pas un tarif modifié');
select t_ok((select count(*) from public.zones where org_id=:'org1')=22, 'rejouer l''ajout réinsère seulement la zone manquante');
select t_fail(u('V1'),'select app.zones_defaut(gen_random_uuid())','permission|denied','la fonction d''ajout n''est pas appelable par un utilisateur');
-- 2. Position GPS du fournisseur
select t_j(u('V1'),$$select to_jsonb(public.maj_adresse_collecte('{"zone":"Cocody","quartier":"Angré","repere":"Face au château d''eau","lat":5.4012,"lng":-3.9821}'::jsonb))$$);
select t_ok((select (adresse_collecte->>'lat')||'/'||(adresse_collecte->>'lng') from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1')='5.401200/-3.982100', 'position GPS du fournisseur enregistrée');
select t_fail(u('V1'),$$select public.maj_adresse_collecte('{"zone":"Cocody","quartier":"A","lat":120,"lng":0}'::jsonb)$$,'GPS invalide','latitude hors limites refusée');
select t_j(u('S'),$$select to_jsonb(public.maj_adresse_collecte('{"zone":"Marcory","quartier":"Zone 4"}'::jsonb,'00000000-0000-0000-0000-0000000000b1'))$$);
select t_ok((select (adresse_collecte->>'zone')||'/'||(adresse_collecte->>'lat') from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1')='Marcory/5.401200', 'modifier l''adresse sans position conserve la position GPS');
select t_j(u('V2'),$$select to_jsonb(public.maj_adresse_collecte('{"zone":"Dabou","lat":5.325,"lng":-4.376}'::jsonb))$$);
select t_ok((select adresse_collecte->>'zone' from public.vendeurs where id='00000000-0000-0000-0000-0000000000b2')='Dabou', 'GPS seul accepté (zone + position suffisent)');
select t_ok((select (adresse_collecte->>'lat') from public.vendeurs where id='00000000-0000-0000-0000-0000000000b1')='5.401200', 'un fournisseur ne modifie pas l''adresse d''un autre');
