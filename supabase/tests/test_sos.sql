-- Tests des alertes SOS des livreurs. Prérequis : stub + les 25 migrations, base neuve.
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
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','K','D','L1','L2','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa','0707000001','Cocody'),('00000000-0000-0000-0000-0000000000a2',:'org1','Kouamé','0707000002','Marcory');
insert into public.membres(user_id,org_id,role,nom,livreur_id) values
 (u('S'),:'org1','superviseur','Awa',null),(u('C'),:'org1','commercial','Koffi',null),(u('P'),:'org1','preparateur','Moussa',null),(u('K'),:'org1','caissier','Yao',null),(u('D'),:'org1','direction','DG',null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1'),(u('L2'),:'org1','livreur','Kouamé','00000000-0000-0000-0000-0000000000a2');
select t_as(u('A')); insert into public.produits(org_id,code,nom,prix) values (:'org1','P1','Riz',14500); select public.ajuster_stock((select id from public.produits limit 1),500,'init'); select t_root();
select t_as(u('C')); insert into public.clients(org_id,nom,tel) values (:'org1','Cli','0505'); select t_root();
insert into public.adresses(org_id,client_id,zone,quartier,defaut) select :'org1',id,'Cocody','R2',true from public.clients;
-- livraison d'une commande ; retourne l'id de livraison prête à confirmer (démarrée)
create or replace function t_pret() returns uuid language plpgsql as $$
declare v uuid; l uuid; begin
  perform t_as(u('C'));
  v := (public.creer_commande(jsonb_build_object('client_id',(select id from public.clients limit 1),'adresse_id',(select id from public.adresses limit 1),'frais',1500,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('produit_id',(select id from public.produits limit 1),'qte',1)))))->>'id';
  perform t_as(u('P')); perform public.commande_action(v,'preparer'); perform public.commande_action(v,'prete');
  perform t_as(u('S')); l := (public.affecter_livraison(v,'00000000-0000-0000-0000-0000000000a1'))->>'livraison_id';
  perform t_as(u('L1')); perform public.livreur_consentement(); perform public.livraison_action(l,'accepter'); perform public.livraison_action(l,'prise_en_charge','{"nb_colis":1}'); perform public.livraison_action(l,'demarrer');
  perform t_root(); return l; end $$;
create or replace function t_conf(l uuid, extra jsonb) returns jsonb language plpgsql as $$
declare r jsonb; v_code text := (select code from public.livraison_codes where livraison_id=l); begin
  perform t_as(u('L1'));
  r := public.livraison_action(l,'confirmer',jsonb_build_object('code',v_code,'montant',16000,'recu_par','Cli') || extra);
  perform t_root(); return r; end $$;
grant execute on function t_pret(), t_conf(uuid,jsonb) to public;


create or replace function t_exec(u uuid, q text) returns void language plpgsql as $$ begin perform t_as(u); execute q; perform t_root(); end $$;
grant execute on function t_exec(uuid,text) to public;
-- 1. Déclenchement
select t_as(u('L1')); select public.sos_declencher('accident','Chute de moto à Angré',5.4012,-3.9821,12) as r1 \gset
select t_root();
select t_ok(:'r1'::jsonb->>'deja'='false', 'le livreur déclenche une alerte SOS');
select t_ok((select statut||'/'||type||'/'||lat from public.alertes_sos)='ouverte/accident/5.401200', 'alerte ouverte avec sa position');
select t_as(u('L1')); select public.sos_declencher('panne') as r2 \gset
select t_root();
select t_ok(:'r2'::jsonb->>'deja'='true' and (select count(*) from public.alertes_sos)=1, 'une seule alerte active par livreur : pas de doublon');
select t_fail(u('L2'),$$select public.sos_declencher('vol')$$,'Type d''alerte invalide','type invalide refusé');
select t_fail(u('L2'),$$select public.sos_declencher('panne','x',120,0)$$,'GPS invalide','position invalide refusée');
select t_fail(u('K'),$$select public.sos_declencher('panne')$$,'Accès|refus|interdit|autoris|droits','seul un livreur déclenche une alerte');
-- 2. Visibilité
select t_ok(t_n(u('S'),'select count(*) from public.alertes_sos')=1, 'le superviseur voit l''alerte');
select t_ok(t_n(u('A'),'select count(*) from public.alertes_sos')=1, 'l''administrateur voit l''alerte');
select t_ok(t_n(u('D'),'select count(*) from public.alertes_sos')=1, 'la direction voit l''alerte');
select t_ok(t_n(u('L1'),'select count(*) from public.alertes_sos')=1, 'le livreur voit sa propre alerte');
select t_ok(t_n(u('L2'),'select count(*) from public.alertes_sos')=0, 'un autre livreur ne voit rien');
select t_ok(t_n(u('K'),'select count(*) from public.alertes_sos')=0, 'le caissier ne voit rien');
select t_ok(t_n(u('B'),'select count(*) from public.alertes_sos')=0, 'une autre société ne voit rien');
select t_fail(u('L1'),$$update public.alertes_sos set statut='cloturee'$$,'permission|denied','modification directe interdite');
-- 3. Traitement
select id as sid from public.alertes_sos \gset
select t_fail(u('K'), format($$select public.sos_traiter(%L,'prendre')$$,:'sid'),'introuvable|Accès|refus|interdit|autoris|droits','le caissier ne traite pas une alerte');
select t_exec(u('S'), format($$select public.sos_traiter(%L,'prendre')$$,:'sid'));
select t_ok((select statut||'/'||prise_par_nom from public.alertes_sos where id=:'sid')='prise/Awa', 'prise en charge par le superviseur');
select t_fail(u('A'), format($$select public.sos_traiter(%L,'prendre')$$,:'sid'),'déjà prise en charge par Awa','pas de double prise en charge');
select t_fail(u('S'), format($$select public.sos_traiter(%L,'cloturer','x')$$,:'sid'),'Précisez','clôture sans précision refusée');
select t_exec(u('S'), format($$select public.sos_traiter(%L,'cloturer','Livreur conduit à la clinique, moto récupérée')$$,:'sid'));
select t_ok((select statut from public.alertes_sos where id=:'sid')='cloturee', 'alerte clôturée avec sa résolution');
select t_fail(u('S'), format($$select public.sos_traiter(%L,'prendre')$$,:'sid'),'déjà traitée','une alerte clôturée ne se rouvre pas');
-- 4. Nouvelle alerte après clôture, fausse alerte par le livreur
select t_as(u('L1')); select public.sos_declencher('autre','Test') as r3 \gset
select t_root();
select t_ok(:'r3'::jsonb->>'deja'='false', 'nouvelle alerte possible après clôture');
select t_exec(u('L1'), format($$select public.sos_traiter(%L,'fausse')$$,:'r3'::jsonb->>'id'));
select t_ok((select statut from public.alertes_sos where id=(:'r3'::jsonb->>'id')::uuid)='fausse', 'le livreur signale une fausse alerte sur la sienne');
select t_as(u('L1')); select public.sos_declencher('malaise') as r4 \gset
select t_root();
select t_fail(u('L2'), format($$select public.sos_traiter(%L,'fausse')$$,:'r4'::jsonb->>'id'),'introuvable|Accès|refus|interdit|autoris|droits','un autre livreur ne peut pas annuler l''alerte d''un collègue');
-- 5. Limite : 5 alertes par heure et par livreur
select t_as(u('L2'));
select public.sos_declencher('autre') as x1 \gset
select public.sos_traiter((:'x1'::jsonb->>'id')::uuid,'fausse');
select public.sos_declencher('autre') as x2 \gset
select public.sos_traiter((:'x2'::jsonb->>'id')::uuid,'fausse');
select public.sos_declencher('autre') as x3 \gset
select public.sos_traiter((:'x3'::jsonb->>'id')::uuid,'fausse');
select public.sos_declencher('autre') as x4 \gset
select public.sos_traiter((:'x4'::jsonb->>'id')::uuid,'fausse');
select public.sos_declencher('autre') as x5 \gset
select public.sos_traiter((:'x5'::jsonb->>'id')::uuid,'fausse');
select t_root();
select t_fail(u('L2'),$$select public.sos_declencher('autre')$$,'Trop d''alertes','au-delà de 5 alertes par heure : appeler directement le superviseur');
