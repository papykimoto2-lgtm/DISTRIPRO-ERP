-- Tests de la commande passée par le client via le lien du fournisseur. Prérequis : stub + les 21 migrations, base neuve.
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
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','V1','V2','L1','B','BV']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa','0707000001','Cocody');
insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',10),('00000000-0000-0000-0000-0000000000b2',:'org1','Concurrent',0),('00000000-0000-0000-0000-0000000000b3',:'org2','Autre',0);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) values
 (u('S'),:'org1','superviseur','Awa',null,null),(u('C'),:'org1','commercial','Koffi',null,null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1',null),
 (u('V1'),:'org1','vendeur','Aya',null,'00000000-0000-0000-0000-0000000000b1'),(u('V2'),:'org1','vendeur','Concurrent',null,'00000000-0000-0000-0000-0000000000b2'),
 (u('BV'),:'org2','vendeur','Autre',null,'00000000-0000-0000-0000-0000000000b3');

-- 1. Lien du fournisseur
select t_j(u('V1'),'select to_jsonb(public.creer_lien_commande())') #>> '{}' as tok1 \gset
select t_ok(:'tok1' ~ '^[a-f0-9]{64}$', 'le fournisseur obtient un lien secret de 256 bits');
select t_ok(t_j(u('V1'),'select to_jsonb(public.creer_lien_commande())') #>> '{}' = :'tok1', 'le lien est stable tant qu''il n''est pas renouvelé');
select t_j(u('V2'),'select to_jsonb(public.creer_lien_commande())') #>> '{}' as tok2 \gset
select t_ok(:'tok1' <> :'tok2', 'chaque fournisseur a son propre lien');
select t_fail(u('L1'), 'select public.creer_lien_commande()', 'Accès refusé|interdit|droits|autoris', 'un livreur ne peut pas créer de lien');
select t_ok(t_j(u('C'),'select to_jsonb(public.creer_lien_commande(''00000000-0000-0000-0000-0000000000b1''))') #>> '{}' = :'tok1', 'l''équipe ANGEL''S peut obtenir le lien d''un fournisseur');
select t_fail(u('C'), 'select public.creer_lien_commande(''00000000-0000-0000-0000-0000000000b3'')', 'Vendeur introuvable', 'impossible pour un fournisseur d''une autre société');
-- 2. Page publique
select t_ok((t_j(null, format('select public.commande_lien_get(%L)',:'tok1')))->>'vendeur'='Aya', 'la page publique identifie le fournisseur');
select t_ok(jsonb_array_length(t_j(null, format('select public.commande_lien_get(%L)',:'tok1'))->'zones')>=1, 'la page publique liste les zones');
select t_ok(t_j(null,'select public.commande_lien_get(''abc'')') is null or t_j(null,'select public.commande_lien_get(''abc'')')='null'::jsonb, 'jeton inconnu : rien');
select t_ok(not (t_j(null, format('select public.commande_lien_get(%L)',:'tok1')))::text ~* 'commission|tel', 'aucune donnée interne exposée');
-- 3. Dépôt par le client (anonyme)
select t_j(null, format($$select public.demande_deposer(%L, '{"nom":"Mariam","tel":"07 07 12 34 56","zone":"Cocody","quartier":"Angré","repere":"Face pharmacie","lat":5.4012,"lng":-3.9821,
   "lignes":[{"desig":"Sac à main","qte":2,"pu":15000,"img":0},{"desig":"Chaussures","qte":1}],"photos":["data:image/jpeg;base64,/9j/4AAQ"],"note":"Livrer après 17h"}'::jsonb)$$,:'tok1')) as r1 \gset
select t_ok(:'r1'::jsonb->>'ok'='true' and length(:'r1'::jsonb->>'ref')=6, 'le client dépose sa demande et reçoit une référence');
select t_ok((select count(*) from public.demandes_commande where vendeur_id='00000000-0000-0000-0000-0000000000b1')=1, 'la demande est enregistrée chez Aya');
select t_ok((select tel||'/'||statut||'/'||lat from public.demandes_commande limit 1)='0707123456/nouvelle/5.401200', 'téléphone nettoyé, statut nouvelle, position GPS conservée');
select t_ok((select count(*) from public.commandes)=0, 'aucune commande n''est créée avant validation du fournisseur');
-- 4. Contrôles
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,'0'||repeat('a',63)), 'expiré ou invalide', 'jeton invalide refusé');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1'), 'votre nom', 'nom obligatoire');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"12","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1'), 'téléphone valide', 'téléphone invalide refusé');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Nulle part","quartier":"A","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1'), 'zone', 'zone inconnue refusée');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1'), 'quartier', 'localisation exigée (quartier, repère ou GPS)');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","lat":95,"lng":0,"lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1'), 'GPS invalide', 'latitude invalide refusée');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[]}'::jsonb)$$,:'tok1'), '1 à 30 articles', 'au moins un article');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":0}]}'::jsonb)$$,:'tok1'), 'Articles invalides', 'quantité nulle refusée');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1,"pu":-5}]}'::jsonb)$$,:'tok1'), 'Articles invalides', 'prix négatif refusé');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}],"photos":["http://evil/x.png"]}'::jsonb)$$,:'tok1'), 'Photo invalide', 'photo non image refusée');
select t_fail(null, format($$select public.demande_deposer(%L,%L::jsonb)$$,:'tok1', json_build_object('nom','X','tel','0707123456','zone','Cocody','quartier','A','lignes',json_build_array(json_build_object('desig','A','qte',1)),'photos',json_build_array('data:image/jpeg;base64,'||repeat('A',600000)))::text), 'trop lourde', 'photo trop lourde refusée');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}],"photos":["data:image/png;base64,AA","data:image/png;base64,AA","data:image/png;base64,AA","data:image/png;base64,AA","data:image/png;base64,AA","data:image/png;base64,AA","data:image/png;base64,AA"]}'::jsonb)$$,:'tok1'), 'Maximum 6', 'plus de 6 photos refusé');
-- 5. Limite de débit : 5 par heure et par téléphone
select t_j(null, format($$select public.demande_deposer(%L,'{"nom":"Spam","tel":"0505000000","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1')) from generate_series(1,5);
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"Spam","tel":"0505000000","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1'), 'Trop de demandes', '6e demande du même téléphone en une heure refusée');
-- 6. Visibilité
select t_ok(t_n(u('V1'),'select count(*) from public.demandes_commande')=6, 'Aya voit ses demandes');
select t_ok(t_n(u('V2'),'select count(*) from public.demandes_commande')=0, 'un autre fournisseur ne voit rien');
select t_ok(t_n(u('C'),'select count(*) from public.demandes_commande')=6, 'l''équipe commerciale voit les demandes');
select t_ok(t_n(u('L1'),'select count(*) from public.demandes_commande')=0, 'un livreur ne voit rien');
select t_ok(t_n(u('B'),'select count(*) from public.demandes_commande')=0, 'une autre société ne voit rien');
select t_fail(null,'select count(*) from public.demandes_commande','permission|denied', 'anonyme : lecture directe des demandes impossible');
select t_fail(null,'select * from public.commande_liens','permission|denied|droit', 'anonyme : table des liens inaccessible');
-- 7. Traitement : le fournisseur crée la commande avec la position GPS
select t_j(u('V1'),$$select public.vendeur_deposer_commande('{"client":{"nom":"Mariam","tel":"0707123456"},"adresse":{"zone":"Cocody","quartier":"Angré","repere":"Face pharmacie","lat":5.4012,"lng":-3.9821},"lignes":[{"desig":"Sac à main","qte":2,"pu":15000},{"desig":"Chaussures","qte":1,"pu":20000}],"pay":"livraison"}'::jsonb)$$)->>'id' as oc \gset
select t_ok((select lat||'/'||lng||'/'||gps_src from public.adresses where client_id=(select client_id from public.commandes where id=:'oc'))='5.401200/-3.982100/client', 'adresse du client géolocalisée à partir de sa position');
select t_ok((select (adr->'gps'->>'lat')::numeric from public.commandes where id=:'oc')=5.4012, 'le livreur recevra la position dans la commande');
select t_fail(u('V1'),$$select public.vendeur_deposer_commande('{"client":{"nom":"M","tel":"0707"},"adresse":{"zone":"Cocody","quartier":"A","lat":200,"lng":0},"lignes":[{"desig":"R","qte":1,"pu":1}]}'::jsonb)$$,'GPS invalide','GPS hors limites refusé côté fournisseur');
select id as did from public.demandes_commande where nom='Mariam' \gset
select t_fail(u('V2'), format('select public.demande_traiter(%L,''traitee'')',:'did'), 'introuvable|Accès|refus', 'un autre fournisseur ne peut pas traiter la demande');
select t_fail(u('V1'), format('select public.demande_traiter(%L,''traitee'',%L)',:'did','00000000-0000-0000-0000-000000000000'), 'Commande introuvable', 'commande inconnue refusée');
select t_j(u('V1'), format('select to_jsonb(public.demande_traiter(%L,''traitee'',%L))',:'did',:'oc'));
select t_ok((select statut||'/'||(commande_id=:'oc')::text from public.demandes_commande where id=:'did')='traitee/true', 'demande traitée et liée à la commande créée');
select t_fail(u('V1'), format('select public.demande_traiter(%L,''rejetee'')',:'did'), 'déjà traitée', 'une demande traitée ne se retraite pas');
select id as did2 from public.demandes_commande where nom='Spam' limit 1 \gset
select t_j(u('V1'), format('select to_jsonb(public.demande_traiter(%L,''rejetee'',null,''Article indisponible''))',:'did2'));
select t_ok((select statut||'/'||motif from public.demandes_commande where id=:'did2')='rejetee/Article indisponible', 'demande rejetée avec motif');
-- 8. Renouvellement : l'ancien lien meurt
select t_j(u('V1'),'select to_jsonb(public.creer_lien_commande(null,true))') #>> '{}' as tok3 \gset
select t_ok(:'tok3' <> :'tok1', 'le renouvellement donne un nouveau lien');
select t_ok(t_j(null, format('select public.commande_lien_get(%L)',:'tok1')) is null or t_j(null, format('select public.commande_lien_get(%L)',:'tok1'))='null'::jsonb, 'l''ancien lien ne fonctionne plus');
select t_fail(null, format($$select public.demande_deposer(%L,'{"nom":"X","tel":"0707123456","zone":"Cocody","quartier":"A","lignes":[{"desig":"A","qte":1}]}'::jsonb)$$,:'tok1'), 'expiré ou invalide', 'dépôt refusé avec l''ancien lien');
-- 9. Adresse avec seulement la position GPS (le client n'a donné ni quartier ni repère)
select t_ok(t_j(u('V1'),$$select public.vendeur_deposer_commande('{"client":{"nom":"Gps","tel":"0707000999"},"adresse":{"zone":"Cocody","lat":5.35,"lng":-3.98},"lignes":[{"desig":"R","qte":1,"pu":1000}]}'::jsonb)$$) ? 'id', 'dépôt accepté avec la seule position GPS');
select t_fail(u('V1'),$$select public.vendeur_deposer_commande('{"client":{"nom":"Rien","tel":"0707000998"},"adresse":{"zone":"Cocody"},"lignes":[{"desig":"R","qte":1,"pu":1000}]}'::jsonb)$$,'quartier ou un point de repère','sans quartier, repère ni GPS : refusé');
