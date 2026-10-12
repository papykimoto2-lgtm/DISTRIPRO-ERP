-- Tests des photos de commande. Prérequis : stub + les sept migrations, base neuve.
\set ON_ERROR_STOP on
create or replace function t_as(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u::text,false); execute 'set role authenticated'; end $$;
create or replace function t_root() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub','',false); end $$;
create or replace function t_ok(c boolean, label text) returns void language plpgsql as $$ begin if c then raise notice 'PASS  %',label; else raise warning 'FAIL  %',label; end if; end $$;
create or replace function t_fail(u uuid, q text, frag text, label text) returns void language plpgsql as $$
declare m text; begin perform t_as(u);
  begin execute q; perform t_root(); raise warning 'FAIL  % (aucune erreur)',label;
  exception when others then get stacked diagnostics m = message_text; perform t_root();
    if m ~* frag then raise notice 'PASS  % [%]',label,left(m,70); else raise warning 'FAIL  % (message: %)',label,m; end if; end; end $$;
create or replace function t_n(u uuid, q text) returns bigint language plpgsql as $$ declare r bigint; begin perform t_as(u); execute q into r; perform t_root(); return r; end $$;
grant execute on function t_as(uuid), t_root(), t_ok(boolean,text), t_fail(uuid,text,text,text), t_n(uuid,text) to public;
create temp table ids(k text primary key, v uuid);
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','K','L1','L2','V1','V2','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa','0707000001','Cocody'),('00000000-0000-0000-0000-0000000000a2',:'org1','Kouamé','0707000002','Marcory');
insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',5),('00000000-0000-0000-0000-0000000000b2',:'org1','Concurrent',0);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) values
 (u('S'),:'org1','superviseur','Awa',null,null),(u('C'),:'org1','commercial','Koffi',null,null),(u('P'),:'org1','preparateur','Moussa',null,null),(u('K'),:'org1','caissier','Yao',null,null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1',null),(u('L2'),:'org1','livreur','Kouamé','00000000-0000-0000-0000-0000000000a2',null),
 (u('V1'),:'org1','vendeur','Aya',null,'00000000-0000-0000-0000-0000000000b1'),(u('V2'),:'org1','vendeur','Concurrent',null,'00000000-0000-0000-0000-0000000000b2');
select t_as(u('A')); insert into public.produits(org_id,code,nom,prix) values (:'org1','P1','Riz',14500); select public.ajuster_stock((select id from public.produits limit 1),100,'init'); select t_root();
\set img 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
-- commande vendeur (V1) via la fonction de dépôt, et commande interne (sans vendeur)
select t_as(u('V1'));
select (public.vendeur_deposer_commande('{"client":{"nom":"Mme Konan","tel":"0707123456"},"adresse":{"zone":"Cocody","quartier":"Angré","repere":""},"lignes":[{"desig":"Robe wax","qte":2,"pu":15000}],"pay":"livraison"}'::jsonb))->>'id' as cv \gset
select t_root();
select t_as(u('C'));
insert into public.clients(org_id,nom,tel) values (:'org1','Interne','0505');
select t_root();
insert into public.adresses(org_id,client_id,zone,quartier,defaut) select :'org1',id,'Cocody','R2',true from public.clients where nom='Interne';
select t_as(u('C'));
select (public.creer_commande(jsonb_build_object('client_id',(select id from public.clients where nom='Interne'),'adresse_id',(select a.id from public.adresses a join public.clients c on c.id=a.client_id where c.nom='Interne'),'frais',1500,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('produit_id',(select id from public.produits limit 1),'qte',1)))))->>'id' as ci \gset
select t_root();
-- 1. Ajout
select t_as(u('V1'));
select public.ajouter_photo_commande(:'cv',:'img') as ph1 \gset
select t_root();
select t_ok((select count(*) from public.commande_photos where commande_id=:'cv')=1, 'le vendeur ajoute une capture à sa commande');
select t_fail(u('V2'), format($$select public.ajouter_photo_commande(%L,%L)$$,:'cv',:'img'), 'Accès refusé', 'un autre vendeur ne peut pas');
select t_fail(u('V1'), format($$select public.ajouter_photo_commande(%L,%L)$$,:'ci',:'img'), 'Accès refusé', 'un vendeur ne peut pas ajouter à une commande interne (sans vendeur)');
select t_fail(u('P'), format($$select public.ajouter_photo_commande(%L,%L)$$,:'cv',:'img'), 'Accès refusé', 'le préparateur ne peut pas');
select t_fail(u('B'), format($$select public.ajouter_photo_commande(%L,%L)$$,:'cv',:'img'), 'introuvable', 'une autre société ne peut pas');
select t_as(u('C')); select public.ajouter_photo_commande(:'cv',:'img'); select public.ajouter_photo_commande(:'ci',:'img'); select t_root();
select t_ok((select count(*) from public.commande_photos)=3, 'le commercial ajoute aussi (3 photos au total)');
select t_fail(u('V1'), format($$select public.ajouter_photo_commande(%L,'<script>alert(1)</script>')$$,:'cv'), 'check', 'contenu non image refusé');
select t_fail(u('V1'), format($$select public.ajouter_photo_commande(%L,%L)$$,:'cv','data'||chr(58)||'image/jpeg;base64,'||repeat('A',300001)), 'check', 'image trop lourde refusée');
-- limite de 8
select t_as(u('V1')); select public.ajouter_photo_commande(:'cv',:'img') from generate_series(1,6); select t_root();
select t_ok((select count(*) from public.commande_photos where commande_id=:'cv')=8, '8 photos atteintes');
select t_fail(u('V1'), format($$select public.ajouter_photo_commande(%L,%L)$$,:'cv',:'img'), 'Maximum 8', 'la 9e est refusée');
-- 2. Lecture
select t_ok(t_n(u('V1'),'select count(*) from public.commande_photos')=8, 'le vendeur lit ses photos');
select t_ok(t_n(u('V2'),'select count(*) from public.commande_photos')=0, 'un autre vendeur ne les voit pas');
select t_ok(t_n(u('K'),'select count(*) from public.commande_photos')=0, 'le caissier ne les voit pas');
select t_ok(t_n(u('P'),'select count(*) from public.commande_photos')=9, 'le préparateur les voit');
select t_ok(t_n(u('B'),'select count(*) from public.commande_photos')=0, 'une autre société non');
select t_ok(t_n(u('L1'),'select count(*) from public.commande_photos')=0, 'le livreur sans mission ne les voit pas');
-- livreur affecté
select t_as(u('S')); select public.commande_action(:'cv','confirmer'); select t_root();
select t_as(u('P')); select public.commande_action(:'cv','preparer'); select public.commande_action(:'cv','prete'); select t_root();
select t_as(u('S')); select public.affecter_livraison(:'cv','00000000-0000-0000-0000-0000000000a1'); select t_root();
select t_ok(t_n(u('L1'),'select count(*) from public.commande_photos')=8, 'le livreur affecté voit les photos de sa mission');
select t_ok(t_n(u('L2'),'select count(*) from public.commande_photos')=0, 'un autre livreur non');
select t_fail(u('L1'), format($$select public.ajouter_photo_commande(%L,%L)$$,:'cv',:'img'), 'Accès refusé', 'le livreur ne peut pas en ajouter');
-- 3. Retrait
select t_fail(u('V1'), format($$select public.retirer_photo_commande(%s)$$,:'ph1'), 'préparation|non modifiable', 'le vendeur ne retire plus une fois la commande prête');
select t_as(u('C')); select public.retirer_photo_commande(:'ph1'); select t_root();
select t_ok((select count(*) from public.commande_photos where id=:'ph1')=0, 'le commercial peut retirer');
select t_fail(u('V2'), format($$select public.retirer_photo_commande(%s)$$,(select min(id) from public.commande_photos)), 'Accès refusé', 'un autre vendeur ne retire pas');
select t_fail(u('K'), $$update public.commande_photos set fichier='x'$$, 'permission denied', 'aucune modification directe');
select t_ok((select count(*) from public.audit_log where action like 'Photo %')>=3, 'ajouts et retraits journalisés');
