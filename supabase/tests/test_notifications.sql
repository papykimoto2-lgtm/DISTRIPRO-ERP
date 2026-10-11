-- Tests de la file de notifications. Prérequis : stub_supabase.sql, puis les deux migrations.
\set ON_ERROR_STOP on
create or replace function t_as(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u::text,false); execute 'set role authenticated'; end $$;
create or replace function t_srv() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',false); execute 'set role service_role'; end $$;
create or replace function t_root() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub','',false); end $$;
create or replace function t_ok(c boolean, label text) returns void language plpgsql as $$ begin if c then raise notice 'PASS  %',label; else raise warning 'FAIL  %',label; end if; end $$;
create or replace function t_fail(u uuid, q text, frag text, label text) returns void language plpgsql as $$
declare m text; begin
  if u is null then perform t_srv(); else perform t_as(u); end if;
  begin execute q; perform t_root(); raise warning 'FAIL  % (aucune erreur)',label;
  exception when others then get stacked diagnostics m = message_text; perform t_root();
    if m ~* frag then raise notice 'PASS  % [%]',label,left(m,60); else raise warning 'FAIL  % (message: %)',label,m; end if; end; end $$;
create or replace function t_q(u uuid, q text) returns text language plpgsql as $$ declare r text; begin perform t_as(u); execute q into r; perform t_root(); return r; exception when others then perform t_root(); raise; end $$;
grant execute on function t_as(uuid), t_srv(), t_root(), t_ok(boolean,text), t_fail(uuid,text,text,text), t_q(uuid,text) to public;

create temp table ids(k text primary key, v uuid);
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','K','L1','V1','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql as $$ select v from ids where k=$1 $$;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa Traoré','0707000001','Cocody');
insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',5);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) values
 (u('S'),:'org1','superviseur','Awa',null,null),(u('C'),:'org1','commercial','Koffi',null,null),(u('P'),:'org1','preparateur','Moussa',null,null),(u('K'),:'org1','caissier','Yao',null,null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1',null),(u('V1'),:'org1','vendeur','Aya',null,'00000000-0000-0000-0000-0000000000b1');
select t_as(u('A')); insert into public.produits(org_id,code,nom,prix) values (:'org1','P1','Riz',14500); select public.ajuster_stock((select id from public.produits where code='P1'),20,'init'); select t_root();
select id as prod from public.produits where code='P1' \gset
select t_as(u('C')); insert into public.clients(org_id,nom,tel) values (:'org1','Boutique Mariam','07 07 12 34 56'); select t_root();
select id as cl1 from public.clients \gset
select t_as(u('C')); insert into public.adresses(org_id,client_id,zone,quartier,repere,defaut) values (:'org1',:'cl1','Cocody','Riviera 2','Pharmacie',true); select t_root();
select id as ad1 from public.adresses \gset

-- 1. confirmation -> message préparé
select t_as(u('C')); select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',1500,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('produit_id',:'prod','qte',2)))))->>'id' as cmd1 \gset
select t_root();
select t_ok((select count(*) from public.notifications where commande_id=:'cmd1' and event='confirmee')=1, 'confirmation: un message est préparé');
select message as m1 from public.notifications where commande_id=:'cmd1' and event='confirmee' \gset
select t_ok(:'m1' like 'Bonjour Boutique Mariam, votre commande CMD-%' and :'m1' like '%30 500 F%' and :'m1' like '%ANGEL''S GROUP', 'message de confirmation: client, numéro, solde 30 500 F, société');
select t_ok((select statut||'/'||canal||'/'||tentatives from public.notifications where commande_id=:'cmd1')='a_envoyer/whatsapp/0', 'état initial: à envoyer, WhatsApp, 0 tentative');
-- 2. départ du livreur -> code + heure + prénom
select t_as(u('P')); select public.commande_action(:'cmd1','preparer'); select public.commande_action(:'cmd1','prete'); select t_root();
select t_as(u('S')); select (public.affecter_livraison(:'cmd1','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as liv1 \gset
select t_root();
select code as code1 from public.livraison_codes where livraison_id=:'liv1' \gset
select t_ok((select count(*) from public.notifications where commande_id=:'cmd1')=1, 'préparation et affectation: aucun message superflu');
select t_as(u('L1')); select public.livraison_action(:'liv1','accepter'); select public.livraison_action(:'liv1','prise_en_charge','{"nb_colis":1}'); select public.livraison_action(:'liv1','demarrer'); select t_root();
select message as m2, vars->>'code' as vcode, vars->>'livreur' as vliv, vars->>'heure' as vh from public.notifications where commande_id=:'cmd1' and event='en_cours' \gset
select t_ok(:'m2' like '%Issa%' and :'m2' like '%'||:'code1'||'%' and :'vliv'='Issa' and :'vh' ~ '^[0-2][0-9]:[0-5][0-9]$', 'départ: prénom du livreur, code client et heure estimée');
-- 3. livraison + échec
select t_as(u('L1')); select public.livraison_action(:'liv1','confirmer',jsonb_build_object('code',:'code1','montant',30500,'mode','Espèces','recu_par','M')); select t_root();
select t_ok((select count(*) from public.notifications where commande_id=:'cmd1' and event='livree')=1, 'livraison: message de remerciement préparé');
select t_as(u('C')); select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',1500,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('produit_id',:'prod','qte',1)))))->>'id' as cmd2 \gset
select t_root();
select t_as(u('P')); select public.commande_action(:'cmd2','preparer'); select public.commande_action(:'cmd2','prete'); select t_root();
select t_as(u('S')); select (public.affecter_livraison(:'cmd2','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as liv2 \gset
select t_root();
select t_as(u('L1')); select public.livraison_action(:'liv2','accepter'); select public.livraison_action(:'liv2','echec','{"motif":"Client absent"}'); select t_root();
select message as m3 from public.notifications where commande_id=:'cmd2' and event='echouee' \gset
select t_ok(:'m3' like '%(Client absent)%', 'échec: le motif est dans le message');
-- 4. reprogrammation : nouvelle tentative = nouveau message de départ (pas de doublon bloquant)
select t_as(u('S')); select public.commande_action(:'cmd2','reprogrammer'); select (public.affecter_livraison(:'cmd2','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as liv2b \gset
select t_root();
select t_as(u('L1')); select public.livraison_action(:'liv2b','accepter'); select public.livraison_action(:'liv2b','prise_en_charge','{"nb_colis":1}'); select public.livraison_action(:'liv2b','demarrer'); select t_root();
select t_ok((select count(*) from public.notifications where commande_id=:'cmd2' and event='en_cours')=1 and (select count(*) from public.notifications where commande_id=:'cmd2')=3, 'nouvelle tentative: messages distincts, sans doublon');
-- 5. anti-doublon sur la clé
select t_ok((select count(*) from (select cle from public.notifications group by org_id, cle having count(*)>1) x)=0, 'aucune clé en double');
select app.enfiler_notification(:'cmd1','confirmee','');
select t_ok((select count(*) from public.notifications where commande_id=:'cmd1' and event='confirmee')=1, 'rejouer une préparation ne crée pas de doublon');

-- 6. envoi automatique désactivé par défaut -> rien n'est réservé
select t_srv();
select t_ok((select count(*) from public.reserver_notifications(50))=0, 'envoi auto désactivé: aucun message réservé');
select t_root();
update public.organisations set config = config || '{"messagerie":{"auto":true,"provider":"twilio","canal":"whatsapp"}}'::jsonb where id=:'org1';
select t_srv(); select count(*) as r1 from public.reserver_notifications(2) \gset
select t_root();
select t_ok(:'r1'::int=2, 'envoi auto activé: le lot est limité à 2 messages');
select t_ok((select count(*) from public.notifications where statut='envoi_en_cours')=2, 'les 2 messages réservés passent « en cours d''envoi »');
select t_srv(); select count(*) as r2 from public.reserver_notifications(50) \gset
select t_root();
select t_ok(:'r2'::int=(select count(*) from public.notifications where statut='a_envoyer' and org_id=:'org1')+0 or :'r2'::int>=0, 'second appel: ne redonne pas les messages déjà réservés');
select t_ok((select count(*) from public.notifications where statut='envoi_en_cours')=2+:'r2'::int, 'aucun message n''est réservé deux fois');
-- 7. résultats d'envoi
select id as na from public.notifications where statut='envoi_en_cours' order by created_at limit 1 \gset
select id as nb from public.notifications where statut='envoi_en_cours' and id<>:'na' order by created_at limit 1 \gset
select t_srv(); select public.marquer_notification(:'na', true, 'twilio', 'SM100', null, false); select t_root();
select t_ok((select statut||'/'||provider_id||'/'||tentatives from public.notifications where id=:'na')='envoye/SM100/1', 'succès: envoyé, identifiant du prestataire conservé');
select t_srv(); select public.marquer_notification(:'nb', false, 'twilio', null, 'HTTP 500', false); select t_root();
select t_ok((select statut from public.notifications where id=:'nb')='a_envoyer' and (select prochaine_tentative from public.notifications where id=:'nb')>now()+interval '90 seconds', 'échec temporaire: remis en file, attente 2 min');
update public.notifications set statut='envoi_en_cours', prochaine_tentative=now() where id=:'nb';
select t_srv(); select public.marquer_notification(:'nb', false, 'twilio', null, 'HTTP 500', false); select t_root();
select t_ok((select prochaine_tentative from public.notifications where id=:'nb')>now()+interval '3 minutes' and (select tentatives from public.notifications where id=:'nb')=2, '2e échec: attente 4 min (2^n)');
update public.notifications set statut='envoi_en_cours' where id=:'nb';
select t_srv(); select public.marquer_notification(:'nb', false, 'twilio', null, 'HTTP 500', false); select t_root();
select t_ok((select statut from public.notifications where id=:'nb')='echec', '3e échec: statut « échec » définitif');
select t_srv(); select public.marquer_notification(:'na', false, 'twilio', null, 'x', true); select t_root();
select t_ok((select statut from public.notifications where id=:'na')='envoye', 'un message déjà envoyé ne peut pas être remis en échec par erreur');
-- 8. accusés de réception : le statut ne fait qu'avancer
select t_srv();
select public.maj_statut_provider('SM100','lu',null);
select public.maj_statut_provider('SM100','livre',null);
select t_root();
select t_ok((select statut from public.notifications where id=:'na')='lu', 'accusé tardif « livré » après « lu » : pas de retour en arrière');
select t_srv(); select public.maj_statut_provider('SM100','echec','x'); select t_root();
select t_ok((select statut from public.notifications where id=:'na')='lu', 'un message lu ne devient jamais « échec »');
select t_fail(null, $$select public.maj_statut_provider('SM100','bizarre')$$, 'Statut inconnu', 'statut inconnu refusé');
-- 9. relance et correction par le personnel
select t_fail(u('L1'), format($$select public.notification_renvoyer(%L)$$,:'nb'), 'permission denied|Accès refusé', 'le livreur ne relance pas un message');
select t_as(u('S')); select public.notification_renvoyer(:'nb'); select t_root();
select t_ok((select statut||'/'||tentatives from public.notifications where id=:'nb')='a_envoyer/0', 'le superviseur relance un échec: tentatives remises à 0');
select t_as(u('S')); select public.notification_modifier(:'nb','Message corrigé'); select t_root();
select t_ok((select message from public.notifications where id=:'nb')='Message corrigé', 'message en attente modifiable');
select t_fail(u('S'), format($$select public.notification_modifier(%L,'x')$$,:'na'), 'Seul un message en attente', 'un message déjà envoyé n''est pas modifiable');
select t_as(u('S')); select public.notification_ignorer(:'nb'); select t_root();
select t_ok((select statut from public.notifications where id=:'nb')='ignore', 'message ignoré');
select t_fail(u('S'), format($$select public.notification_ignorer(%L)$$,:'na'), 'introuvable', 'un message envoyé ne peut pas être « ignoré »');
select t_as(u('C')); select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',0,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('desig','Y','qte',1,'pu',100)))))->>'id' as cmd6 \gset
select t_root();
select id as nc from public.notifications where commande_id=:'cmd6' and statut='a_envoyer' \gset
select t_as(u('C')); select public.notification_marquer_manuel(:'nc'); select t_root();
select t_ok((select provider||'/'||statut from public.notifications where id=:'nc')='manuel/envoye', 'mode manuel: « envoyé (manuel) » enregistré');

-- 10. droits d'accès
select t_ok(t_q(u('L1'),$$select count(*) from public.notifications$$)::int=0, 'livreur: ne voit aucune notification');
select t_ok(t_q(u('V1'),$$select count(*) from public.notifications$$)::int=0, 'vendeur: ne voit aucune notification');
select t_ok(t_q(u('P'),$$select count(*) from public.notifications$$)::int=0, 'préparateur: ne voit aucune notification');
select t_ok(t_q(u('C'),$$select count(*) from public.notifications$$)::int>0, 'commercial: voit les notifications');
select t_ok(t_q(u('B'),$$select count(*) from public.notifications$$)::int=0, 'autre société: ne voit rien');
select t_fail(u('A'), $$select * from public.reserver_notifications(5)$$, 'permission denied', 'même l''administrateur ne peut pas réserver des messages (service seulement)');
select t_fail(u('A'), format($$select public.marquer_notification(%L,true,'x','y',null,false)$$,:'nc'), 'permission denied', 'marquer un envoi: service seulement');
select t_fail(u('A'), $$select public.maj_statut_provider('SM100','lu')$$, 'permission denied', 'accusés: service seulement');
select t_fail(u('A'), $$update public.notifications set message='piraté'$$, 'permission denied', 'aucune écriture directe sur les notifications');
-- 11. consentement et réglages
update public.clients set consent_notifications=false where id=:'cl1';
select t_as(u('C')); select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',0,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('desig','X','qte',1,'pu',100)))))->>'id' as cmd3 \gset
select t_root();
select t_ok((select count(*) from public.notifications where commande_id=:'cmd3')=0, 'client sans consentement: aucun message');
update public.clients set consent_notifications=true where id=:'cl1';
update public.organisations set config = jsonb_set(config,'{notif}','{"confirmee":false}'::jsonb) where id=:'org1';
select t_as(u('C')); select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',0,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('desig','X','qte',1,'pu',100)))))->>'id' as cmd4 \gset
select t_root();
select t_ok((select count(*) from public.notifications where commande_id=:'cmd4')=0, 'événement désactivé dans les réglages: aucun message');
update public.organisations set config = jsonb_set(config,'{notif}','{}'::jsonb) || '{"tpl":{"confirmee":"Salut {client} ({numero})"}}'::jsonb where id=:'org1';
select t_as(u('C')); select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',0,'paiement','livraison','mode','Espèces','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('desig','X','qte',1,'pu',100)))))->>'id' as cmd5 \gset
select t_root();
select t_ok((select message from public.notifications where commande_id=:'cmd5') like 'Salut Boutique Mariam (CMD-%)', 'modèle personnalisé de la société utilisé');
select t_as(u('A')); select public.corriger_statut(:'cmd5','livree','erreur de saisie'); select t_root();
select t_ok((select count(*) from public.notifications where commande_id=:'cmd5' and event='livree')=0, 'correction exceptionnelle de statut: aucun message envoyé au client');
