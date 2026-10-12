-- Tests des collectes chez les vendeurs. Prérequis : stub + les huit migrations, base neuve.
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
create or replace function t_j(u uuid, q text) returns jsonb language plpgsql as $$ declare r jsonb; begin perform t_as(u); execute q into r; perform t_root(); return r; end $$;
grant execute on function t_as(uuid), t_root(), t_ok(boolean,text), t_fail(uuid,text,text,text), t_n(uuid,text), t_j(uuid,text) to public;
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
create or replace function t_vcmd(k text, nom text) returns uuid language plpgsql as $$
declare v uuid; begin perform t_as(u(k));
  v := (public.vendeur_deposer_commande(jsonb_build_object('client',jsonb_build_object('nom',nom,'tel','0707123456'),'adresse',jsonb_build_object('zone','Cocody','quartier','Angré','repere',''),'lignes',jsonb_build_array(jsonb_build_object('desig','Robe','qte',1,'pu',15000)),'pay','livraison')))->>'id';
  perform t_root(); return v; end $$;
grant execute on function t_vcmd(text,text) to public;
select t_vcmd('V1','Cli 1') as o1 \gset
select t_vcmd('V1','Cli 2') as o2 \gset
select t_vcmd('V1','Cli 3') as o3 \gset
select t_vcmd('V2','Cli X') as ox \gset
-- confirmation par le superviseur (o1, o2, ox) ; o3 reste en attente
select t_as(u('S')); select public.commande_action(:'o1','confirmer'); select public.commande_action(:'o2','confirmer'); select public.commande_action(:'ox','confirmer'); select t_root();
\set adr '{"zone":"Cocody","quartier":"Angré 8e tranche","repere":"près de la pharmacie"}'
-- 1. Adresse de collecte
select t_fail(u('P'), format($$select public.maj_adresse_collecte(%L::jsonb)$$,:'adr'), 'Accès refusé|Vendeur introuvable', 'le préparateur ne modifie pas d''adresse');
select t_fail(u('V1'), $$select public.maj_adresse_collecte('{"zone":"Cocody"}'::jsonb)$$, 'quartier', 'adresse sans quartier ni repère refusée');
select t_fail(u('C'), format($$select public.maj_adresse_collecte(%L::jsonb, null)$$,:'adr'), 'introuvable', 'le commercial doit désigner un vendeur');
-- 2. Planification : refus
select t_fail(u('S'), format($$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[%L]::uuid[],'00000000-0000-0000-0000-0000000000a1',now()+interval '1 hour')$$,:'o1'), 'Adresse de collecte', 'adresse de collecte manquante : refusé');
select t_as(u('V1')); select public.maj_adresse_collecte(:'adr'::jsonb); select t_root();
select t_ok((select adresse_collecte->>'quartier' from public.vendeurs where nom='Aya')='Angré 8e tranche', 'le vendeur renseigne son adresse de collecte');
select t_fail(u('C'), format($$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[%L]::uuid[],'00000000-0000-0000-0000-0000000000a1',now())$$,:'o1'), 'Accès refusé', 'le commercial ne planifie pas');
select t_fail(u('P'), format($$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[%L]::uuid[],'00000000-0000-0000-0000-0000000000a1',now())$$,:'o1'), 'Accès refusé', 'le préparateur ne planifie pas');
select t_fail(u('S'), format($$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[%L]::uuid[],'00000000-0000-0000-0000-0000000000a1',now())$$,:'o3'), 'confirmée', 'commande non confirmée refusée');
select t_fail(u('S'), format($$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[%L]::uuid[],'00000000-0000-0000-0000-0000000000a1',now())$$,:'ox'), 'n''appartient pas', 'commande d''un autre vendeur refusée');
select t_fail(u('S'), $$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[]::uuid[],'00000000-0000-0000-0000-0000000000a1',now())$$, 'au moins une', 'sélection vide refusée');
select t_fail(u('B'), format($$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[%L]::uuid[],'00000000-0000-0000-0000-0000000000a1',now())$$,:'o1'), 'Accès refusé|introuvable', 'une autre société ne planifie pas');
-- 3. Planification : succès
select t_as(u('S'));
select (public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[:'o1',:'o2']::uuid[],'00000000-0000-0000-0000-0000000000a1',now()+interval '1 hour','Passer avant 16 h'))->>'id' as col \gset
select t_root();
select t_ok((select numero from public.collectes where id=:'col') ~ '^COL-\d{4}-0001$', 'collecte numérotée');
select t_ok((select count(*) from public.collecte_commandes where collecte_id=:'col')=2, 'deux commandes rattachées');
select t_ok((select vendeur_nom||'/'||livreur_prenom from public.collectes where id=:'col')='Aya/Issa', 'noms du vendeur et prénom du livreur conservés');
select t_ok((select resume from public.collecte_commandes where collecte_id=:'col' limit 1)='1× Robe', 'résumé des articles conservé pour le livreur');
select t_fail(u('S'), format($$select public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[%L]::uuid[],'00000000-0000-0000-0000-0000000000a2',now())$$,:'o1'), 'déjà en cours', 'une commande ne peut pas être dans deux collectes');
-- 4. Visibilité
select t_ok(t_n(u('L1'),'select count(*) from public.collectes')=1, 'le livreur missionné voit la collecte');
select t_ok(t_n(u('L2'),'select count(*) from public.collectes')=0, 'un autre livreur non');
select t_ok(t_n(u('V1'),'select count(*) from public.collectes')=1, 'le vendeur voit sa collecte');
select t_ok(t_n(u('V2'),'select count(*) from public.collectes')=0, 'un autre vendeur non');
select t_ok(t_n(u('K'),'select count(*) from public.collectes')=0, 'le caissier non');
select t_ok(t_n(u('V1'),'select count(*) from public.collecte_codes')=1, 'le vendeur voit son code de remise');
select t_ok(t_n(u('L1'),'select count(*) from public.collecte_codes')=0, 'le livreur ne voit PAS le code');
select t_ok(t_n(u('P'),'select count(*) from public.collecte_codes')=0, 'le préparateur non plus');
select t_ok(t_n(u('S'),'select count(*) from public.collecte_codes')=1, 'le superviseur le voit (cas de litige)');
select t_ok(t_n(u('V2'),'select count(*) from public.collecte_codes')=0, 'un autre vendeur non');
select code as bon from public.collecte_codes where collecte_id=:'col' \gset
-- 5. Déroulé
select t_fail(u('L2'), format($$select public.collecte_action(%L,'accepter')$$,:'col'), 'Accès refusé', 'un autre livreur ne peut pas accepter');
select t_fail(u('L1'), format($$select public.collecte_action(%L,'partir')$$,:'col'), 'Acceptez', 'départ avant acceptation refusé');
select t_as(u('L1')); select public.collecte_action(:'col','accepter'); select public.collecte_action(:'col','partir'); select t_root();
select t_ok((select statut from public.collectes where id=:'col')='en_route', 'accepté puis en route');
select t_ok(t_j(u('L1'),format($$select public.collecte_action(%L,'collecter',jsonb_build_object('code','xxxx','colis',jsonb_build_object(%L,1,%L,2)))$$,:'col',:'o1',:'o2'))->>'ok'='false', 'mauvais code : refusé sans erreur');
select t_ok((select essais_code from public.collectes where id=:'col')=1, 'l''essai est compté');
select t_fail(u('L1'), format($$select public.collecte_action(%L,'collecter',jsonb_build_object('code',%L,'colis',jsonb_build_object(%L,0,%L,0)))$$,:'col',:'bon',:'o1',:'o2'), 'au moins une', 'aucun colis : refusé');
select t_ok(t_j(u('L1'),format($$select public.collecte_action(%L,'collecter',jsonb_build_object('code',%L,'colis',jsonb_build_object(%L,2,%L,0)))$$,:'col',:'bon',:'o1',:'o2'))->>'ok'='true', 'bon code : colis collectés (2 pour o1, 0 pour o2)');
select t_ok((select statut from public.collectes where id=:'col')='collectee', 'statut « collectée »');
select t_fail(u('L1'), format($$select public.collecte_action(%L,'recevoir')$$,:'col'), 'Accès refusé', 'le livreur ne réceptionne pas');
select t_fail(u('S'), format($$select public.collecte_action(%L,'recevoir')$$,:'col'), 'Accès refusé', 'le superviseur ne réceptionne pas (préparateur ou administrateur)');
select t_as(u('P')); select public.collecte_action(:'col','recevoir'); select t_root();
select t_ok((select statut from public.collectes where id=:'col')='recue', 'collecte réceptionnée');
select t_ok((select statut from public.commandes where id=:'o1')='preparation', 'la commande complète passe en préparation');
select t_ok((select statut from public.commandes where id=:'o2')='confirmee', 'la commande sans colis reste confirmée');
select t_fail(u('P'), format($$select public.collecte_action(%L,'recevoir')$$,:'col'), 'pas arrivée', 'pas de seconde réception');
-- 6. Réaffectation, annulation, échec
select t_as(u('S'));
select (public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[:'o2']::uuid[],'00000000-0000-0000-0000-0000000000a1',now()+interval '2 hour'))->>'id' as col2 \gset
select t_root();
select t_fail(u('L1'), format($$select public.collecte_action(%L,'refuser','{"motif":""}')$$,:'col2'), 'Motif', 'refus sans motif impossible');
select t_as(u('L1')); select public.collecte_action(:'col2','refuser','{"motif":"Moto en panne"}'); select t_root();
select t_ok((select statut from public.collectes where id=:'col2')='echouee', 'refus du livreur : collecte « non réalisée »');
select t_fail(u('C'), format($$select public.collecte_action(%L,'reaffecter',jsonb_build_object('livreur','00000000-0000-0000-0000-0000000000a2'))$$,:'col2'), 'Accès refusé', 'le commercial ne réaffecte pas');
select t_as(u('S')); select public.collecte_action(:'col2','reaffecter',jsonb_build_object('livreur','00000000-0000-0000-0000-0000000000a2')); select t_root();
select t_ok((select statut||livreur_id::text||livreur_prenom from public.collectes where id=:'col2')='planifiee00000000-0000-0000-0000-0000000000a2Kouamé', 'réaffectée au livreur 2, de nouveau planifiée');
select t_fail(u('S'), format($$select public.collecte_action(%L,'annuler','{}')$$,:'col2'), 'Motif', 'annulation sans motif refusée');
select t_as(u('S')); select public.collecte_action(:'col2','annuler','{"motif":"Vendeur injoignable"}'); select t_root();
select t_ok((select statut from public.collectes where id=:'col2')='annulee', 'collecte annulée');
select t_as(u('S'));
select (public.planifier_collecte('00000000-0000-0000-0000-0000000000b1',array[:'o2']::uuid[],'00000000-0000-0000-0000-0000000000a1',now()+interval '3 hour'))->>'id' as col3 \gset
select t_root();
select t_ok((select count(*) from public.collectes where statut='annulee')=1, 'après annulation, la commande peut être replanifiée');
-- 7. 5 essais de code
select t_as(u('L1')); select public.collecte_action(:'col3','accepter'); select t_root();
select t_as(u('L1'));
select public.collecte_action(:'col3','collecter','{"code":"0","colis":{}}') from generate_series(1,5);
select t_root();
select t_fail(u('L1'), format($$select public.collecte_action(%L,'collecter','{"code":"0","colis":{}}')$$,:'col3'), 'Trop d''essais', 'au-delà de 5 essais : bloqué');
select t_ok((select count(*) from public.audit_log where action in ('Collecte planifiée','Colis collectés','Collecte réceptionnée','Collecte annulée','Collecte non réalisée'))>=5, 'les étapes sont journalisées');
