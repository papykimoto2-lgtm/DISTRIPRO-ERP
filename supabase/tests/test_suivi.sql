-- Tests du suivi client et des avis. Prérequis : stub_supabase.sql puis les cinq migrations, sur une base neuve.
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

create temp table ids(k text primary key, v uuid);
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','D','L1','V1','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa Traoré','0707000001','Cocody');
insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',5);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) values
 (u('S'),:'org1','superviseur','Awa',null,null),(u('C'),:'org1','commercial','Koffi',null,null),(u('P'),:'org1','preparateur','Moussa',null,null),(u('D'),:'org1','direction','DG',null,null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1',null),(u('V1'),:'org1','vendeur','Aya',null,'00000000-0000-0000-0000-0000000000b1');
select t_as(u('A')); insert into public.produits(org_id,code,nom,prix) values (:'org1','P1','Riz 25 kg',14500); select public.ajuster_stock((select id from public.produits where code='P1'),500,'init'); select t_root();
select t_as(u('C')); insert into public.clients(org_id,nom,tel) values (:'org1','Boutique Mariam','0505111111'); select t_root();
insert into public.adresses(org_id,client_id,zone,quartier,repere,defaut,lat,lng) select :'org1',id,'Cocody','Riviera 2','Pharmacie',true,5.36,-3.97 from public.clients;
create or replace function t_cmd() returns uuid language plpgsql as $$
declare v_id uuid; begin perform t_as(u('C'));
  v_id := (public.creer_commande(jsonb_build_object('client_id',(select id from public.clients limit 1),'adresse_id',(select id from public.adresses limit 1),'frais',1500,'paiement','livraison','mode','Espèces','confirmer',true,
          'lignes',jsonb_build_array(jsonb_build_object('produit_id',(select id from public.produits limit 1),'qte',1)))))->>'id';
  perform t_root(); return v_id; end $$;

select t_cmd() as o1 \gset
-- 1. Création du lien
select t_fail(u('P'), format($$select public.creer_lien_suivi(%L)$$,:'o1'), 'Accès refusé', 'le préparateur ne crée pas de lien de suivi');
select t_fail(u('V1'), format($$select public.creer_lien_suivi(%L)$$,:'o1'), 'Accès refusé', 'un vendeur ne crée pas de lien pour la commande d''un autre');
select t_fail(u('B'), format($$select public.creer_lien_suivi(%L)$$,:'o1'), 'introuvable', 'une autre société ne crée pas de lien');
select t_as(u('C')); select public.creer_lien_suivi(:'o1') as tok \gset
select t_root();
select t_ok(:'tok' ~ '^[a-f0-9]{64}$', 'jeton de 256 bits');
select t_as(u('S')); select t_ok(public.creer_lien_suivi(:'o1') = :'tok', 'même jeton pour la même commande'); select t_root();
-- 2. Page publique : confirmée
select t_ok((public.suivi_get(:'tok'))->>'statut'='confirmee', 'le client voit « confirmée »');
select t_ok(t_j(null, format($$select public.suivi_get(%L)$$,:'tok'))->>'numero' is not null, 'lisible sans connexion');
select t_ok(public.suivi_get('x'||repeat('0',63)) is null, 'jeton inconnu : rien');
select t_ok(public.suivi_get(:'tok') ->> 'livreur' is null, 'pas de livreur avant l''affectation');
select t_fail(null, $$select count(*) from public.suivi_liens$$, 'permission denied', 'la table des liens n''est pas lisible par le public');
select t_fail(u('C'), $$select token from public.suivi_liens$$, 'permission denied', 'ni par un employé');
-- 3. Cycle de livraison
select t_as(u('P')); select public.commande_action(:'o1','preparer'); select public.commande_action(:'o1','prete'); select t_root();
select t_as(u('S')); select (public.affecter_livraison(:'o1','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as lv \gset
select t_root();
select t_ok((public.suivi_get(:'tok'))->>'livreur'='Issa', 'prénom du livreur seulement');
select t_ok(position('Traoré' in (public.suivi_get(:'tok'))::text)=0 and position('0707' in (public.suivi_get(:'tok'))::text)=0, 'ni le nom de famille ni le téléphone');
select t_as(u('L1')); select public.livreur_consentement(); select public.livraison_action(:'lv','accepter'); select public.livraison_action(:'lv','prise_en_charge','{"nb_colis":1}'); select public.livraison_action(:'lv','demarrer'); select t_root();
select t_ok((public.suivi_get(:'tok'))->'pos' = 'null'::jsonb, 'en route, sans position reçue : pas de position');
select t_as(u('L1')); select public.enregistrer_position(5.351, -3.98, 10); select t_root();
select t_ok(((public.suivi_get(:'tok'))->'pos'->>'lat')::numeric = 5.351, 'position du livreur visible pendant la course');
select t_ok((public.suivi_get(:'tok'))->>'eta' is not null, 'heure d''arrivée estimée');
select t_ok(((public.suivi_get(:'tok'))->'dest'->>'lat')::numeric = 5.36, 'destination affichée');
select t_ok(position('code' in lower((public.suivi_get(:'tok'))::text))=0, 'le code de livraison n''est jamais exposé');
select t_ok(((public.suivi_get(:'tok'))->>'peut_noter')::boolean is false, 'pas de note avant la livraison');
select t_ok(not public.suivi_noter(:'tok', 5, 'top'), 'note refusée avant la livraison');
select code as ecode from public.livraison_codes where livraison_id=:'lv' \gset
select t_as(u('L1')); select public.livraison_action(:'lv','confirmer',jsonb_build_object('code',:'ecode','montant',16000,'mode','Espèces','recu_par','Mariam')); select t_root();
select t_ok((public.suivi_get(:'tok'))->>'statut'='livree', 'livrée');
select t_ok((public.suivi_get(:'tok'))->'pos' = 'null'::jsonb, 'plus de position une fois livré');
select t_ok(((public.suivi_get(:'tok'))->>'peut_noter')::boolean, 'le client peut noter');
-- 4. Avis
select t_fail(null, format($$select public.suivi_noter(%L, 6)$$,:'tok'), 'invalide', 'note hors 1-5 refusée');
select t_ok(t_j(null, format($$select to_jsonb(public.suivi_noter(%L, 4, 'Rapide et aimable'))$$,:'tok')) = 'true'::jsonb, 'avis enregistré sans connexion');
select t_ok(not public.suivi_noter(:'tok', 1, 'autre'), 'un seul avis par livraison');
select t_ok((select note from public.avis_livraison)=4, 'la note conservée est la première');
select t_ok(((public.suivi_get(:'tok'))->>'peut_noter')::boolean is false and (public.suivi_get(:'tok'))->'avis'->>'note'='4', 'la page montre l''avis donné');
select t_ok((select count(*) from public.audit_log where action='Avis client')=1, 'avis journalisé');
select t_fail(u('S'), $$update public.avis_livraison set note=5$$, 'ajout|interdit|permission denied', 'un avis ne se modifie pas');
select t_fail(u('S'), $$delete from public.avis_livraison$$, 'ajout|interdit|permission denied', 'un avis ne se supprime pas');
select t_ok((select count(*) from (select 1 from public.avis_livraison) x)=1, 'avis intact');
select t_as(u('S')); select t_ok((select count(*) from public.avis_livraison)=1,'le superviseur lit les avis'); select t_root();
select t_as(u('D')); select t_ok((select count(*) from public.avis_livraison)=1,'la direction lit les avis'); select t_root();
select t_as(u('L1')); select t_ok((select count(*) from public.avis_livraison)=1,'le livreur lit ses propres avis'); select t_root();
select t_as(u('C')); select t_ok((select count(*) from public.avis_livraison)=0,'le commercial ne lit pas les avis'); select t_root();
select t_as(u('B')); select t_ok((select count(*) from public.avis_livraison)=0,'une autre société ne les lit pas'); select t_root();
-- 5. Expiration
update public.suivi_liens set expires_at = now() - interval '1 minute';
select t_ok(public.suivi_get(:'tok') is null, 'lien expiré : rien');
