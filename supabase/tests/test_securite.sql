\set ON_ERROR_STOP on
create or replace function t_as(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u::text,false); execute 'set role authenticated'; end $$;
create or replace function t_anon() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',false); execute 'set role anon'; end $$;
create or replace function t_root() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub','',false); end $$;
create or replace function t_ok(c boolean, label text) returns void language plpgsql as $$ begin if c then raise notice 'PASS  %',label; else raise warning 'FAIL  %',label; end if; end $$;
-- exécute un SQL en tant qu'utilisateur et attend un échec contenant `frag`
create or replace function t_fail(u uuid, q text, frag text, label text) returns void language plpgsql as $$
declare m text; begin
  perform t_as(u);
  begin execute q; perform t_root(); raise warning 'FAIL  % (aucune erreur)',label;
  exception when others then get stacked diagnostics m = message_text; perform t_root();
    if m ~* frag then raise notice 'PASS  % [%]',label,left(m,70); else raise warning 'FAIL  % (message: %)',label,m; end if; end; end $$;
create or replace function t_q(u uuid, q text) returns text language plpgsql as $$ declare r text; begin perform t_as(u); execute q into r; perform t_root(); return r; exception when others then perform t_root(); raise; end $$;

grant execute on function t_as(uuid), t_anon(), t_root(), t_ok(boolean,text), t_fail(uuid,text,text,text), t_q(uuid,text) to public;
-- Utilisateurs
create temp table ids(k text primary key, v uuid);
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','K','D','L1','L2','V1','V2','B','X']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql as $$ select v from ids where k=$1 $$;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin', '0584163232') as org1 \gset
select public.amorcer_organisation('AUTRE SOCIETE', u('B'), 'Admin B') as org2 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa','0707000001','Cocody'),('00000000-0000-0000-0000-0000000000a2',:'org1','Kouamé','0707000002','Marcory');
insert into public.vendeurs(id,org_id,nom,tel,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya Boutique','0707555555',5),('00000000-0000-0000-0000-0000000000b2',:'org1','Concurrent','0707666666',0);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) values
 (u('S'),:'org1','superviseur','Awa',null,null),(u('C'),:'org1','commercial','Koffi',null,null),(u('P'),:'org1','preparateur','Moussa',null,null),
 (u('K'),:'org1','caissier','Yao',null,null),(u('D'),:'org1','direction','DG',null,null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1',null),(u('L2'),:'org1','livreur','Kouamé','00000000-0000-0000-0000-0000000000a2',null),
 (u('V1'),:'org1','vendeur','Aya',null,'00000000-0000-0000-0000-0000000000b1'),(u('V2'),:'org1','vendeur','Concurrent',null,'00000000-0000-0000-0000-0000000000b2')
 on conflict do nothing;

-- ================= Référentiels =================
select t_as(u('A'));
insert into public.produits(org_id,code,nom,prix,seuil) values (:'org1','P-RIZ','Riz 25 kg',14500,5);
select t_root();
select t_fail(u('A'), $$update public.produits set stock=999$$, 'permission denied', 'stock non modifiable en direct');
select t_ok(t_q(u('L1'),$$select count(*) from public.produits$$)::int=0, 'livreur: 0 produit visible');
select t_fail(u('K'), $$insert into public.produits(org_id,code,nom,prix) values ((select app.org()),'X','x',1)$$, 'row-level security', 'caissier ne peut pas créer de produit');
select id as prod from public.produits where code='P-RIZ' \gset
select t_as(u('A')); select public.ajuster_stock(:'prod', 20, 'inventaire initial'); select t_root();
select t_ok((select stock from public.produits where id=:'prod')=20, 'ajuster_stock met le stock à 20');
select t_fail(u('S'), format($$select public.ajuster_stock(%L,5,'x')$$,:'prod'), 'Accès refusé', 'superviseur ne peut pas ajuster le stock');

select t_as(u('C'));
insert into public.clients(org_id,nom,tel) values (:'org1','Boutique Mariam','0505111111');
select t_root();
select id as cl1 from public.clients where nom='Boutique Mariam' \gset
select t_as(u('C'));
insert into public.adresses(org_id,client_id,libelle,zone,quartier,repere,defaut) values (:'org1',:'cl1','Boutique','Cocody','Riviera 2','Face pharmacie',true);
select t_root();
select id as ad1 from public.adresses where client_id=:'cl1' \gset

-- ================= Cycle de vie d'une commande =================
select t_as(u('C'));
select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',1500,'remise',0,'paiement','livraison','mode','Espèces','canal','WhatsApp','confirmer',true,
   'lignes', jsonb_build_array(jsonb_build_object('produit_id',:'prod','qte',2)))))->>'id' as cmd1 \gset
select t_root();
select t_ok((select statut from public.commandes where id=:'cmd1')='confirmee' and (select total from public.commandes where id=:'cmd1')=30500, 'commande confirmée, total recalculé côté serveur (30 500)');
select t_fail(u('C'), format($$update public.commandes set statut='livree' where id=%L$$,:'cmd1'), 'permission denied', 'statut non modifiable en direct');
select t_fail(u('C'), format($$select public.commande_action(%L,'prete')$$,:'cmd1'), 'Accès refusé', 'le commercial ne prépare pas');
select t_fail(u('P'), format($$select public.commande_action(%L,'prete')$$,:'cmd1'), 'doit être en préparation', 'prête sans préparation refusée');
select t_as(u('P')); select public.commande_action(:'cmd1','preparer'); select public.commande_action(:'cmd1','prete'); select t_root();
select t_ok((select stock from public.produits where id=:'prod')=18 and (select stock_sorti from public.commandes where id=:'cmd1'), 'stock sorti à la préparation (20 -> 18)');
select t_fail(u('S'), format($$select public.affecter_livraison(%L,%L)$$,:'cmd1','00000000-0000-0000-0000-0000000000a1'), 'indisponible|introuvable', 'placeholder') where false;
select t_as(u('S')); select (public.affecter_livraison(:'cmd1','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as liv1 \gset
select t_root();
select code as code1 from public.livraison_codes where livraison_id=:'liv1' \gset
select t_ok(:'code1' ~ '^[0-9]{4}$', 'code client à 4 chiffres généré');
select t_ok((select montant_attendu from public.livraisons where id=:'liv1')=30500, 'montant à encaisser = 30 500');

-- isolation entre livreurs
select t_ok(t_q(u('L2'),$$select count(*) from public.livraisons$$)::int=0, 'livreur 2 ne voit pas la mission du livreur 1');
select t_ok(t_q(u('L1'),$$select count(*) from public.livraisons$$)::int=1, 'livreur 1 voit sa mission');
select t_ok(t_q(u('L1'),$$select count(*) from public.livraison_codes$$)::int=0, 'livreur: 0 ligne dans livraison_codes');
select t_fail(u('L2'), format($$select public.livraison_action(%L,'accepter')$$,:'liv1'), 'Mission introuvable', 'livreur 2 ne peut pas accepter la mission de 1');
select t_ok(t_q(u('L1'),$$select count(*) from public.clients$$)::int=1, 'livreur voit le client de sa mission seulement');
select t_ok(t_q(u('L2'),$$select count(*) from public.clients$$)::int=0, 'livreur 2 ne voit aucun client');

-- parcours livreur
select t_fail(u('L1'), format($$select public.livraison_action(%L,'demarrer')$$,:'liv1'), 'Confirmez d|déjà|impossible', 'demarrage sans acceptation refusé') ;
select t_as(u('L1'));
select public.livraison_action(:'liv1','accepter');
select public.livraison_action(:'liv1','prise_en_charge','{"nb_colis":1}');
select public.livraison_action(:'liv1','demarrer');
select t_root();
select t_fail(u('L1'), $$select public.enregistrer_position(5.30,-3.98,10)$$, 'Consentement', 'GPS refusé sans consentement');
select t_as(u('L1')); select public.livreur_consentement(); select public.enregistrer_position(5.30,-3.98,10); select t_root();
select t_ok((select count(*) from public.positions_gps)=1, 'position enregistrée (course en cours + consentement)');
select t_ok(t_q(u('L1'),$$select count(*) from public.positions_gps$$)::int=0, 'livreur ne relit pas les positions');
select t_ok(t_q(u('S'),$$select count(*) from public.dernieres_positions()$$)::int=1, 'superviseur voit la dernière position');
select t_fail(u('C'), $$select * from public.dernieres_positions()$$, 'Accès refusé', 'commercial ne voit pas le GPS');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer','{"code":"%s","montant":30500,"mode":"Espèces","recu_par":"X"}')$$,:'liv1',:'code1'||'x'), 'xx', 'placeholder') where false;
select t_as(u('L1')); select (public.livraison_action(:'liv1','confirmer','{"code":"0000x","montant":30500,"mode":"Espèces","recu_par":"X"}'))->>'erreur' as err1 \gset
select t_root();
select t_ok(:'err1'='Code de confirmation incorrect', 'mauvais code: refusé sans lever d''erreur');
select t_ok((select essais_code from public.livraisons where id=:'liv1')=1, 'le mauvais essai est bien compté');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',1000,'mode','Espèces','recu_par','X'))$$,:'liv1',:'code1'), 'explication obligatoire', 'écart sans explication refusé');
select t_as(u('L1'));
select public.livraison_action(:'liv1','confirmer',jsonb_build_object('code',:'code1','montant',30500,'mode','Espèces','recu_par','Mariam'));
select t_root();
select t_ok((select statut from public.commandes where id=:'cmd1')='livree' and (select statut from public.livraisons where id=:'liv1')='livree', 'livraison confirmée -> commande livrée');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',30500,'mode','Espèces','recu_par','Mariam'))$$,:'liv1',:'code1'), 'pas en cours', 'double validation refusée');
select t_ok((select count(*) from public.fonds where type='encaissement' and montant=30500)=1, 'un seul encaissement enregistré');
select t_ok(t_q(u('L2'),$$select count(*) from public.fonds$$)::int=0, 'livreur 2 ne voit pas les fonds du livreur 1');
select t_ok(t_q(u('L1'),$$select count(*) from public.fonds$$)::int=1, 'livreur 1 voit son encaissement');
select t_fail(u('A'), $$update public.fonds set montant=1$$, 'permission denied', 'fonds: modification interdite (droits)');
select t_root();
do $$ begin begin update public.fonds set montant=1; raise warning 'FAIL fonds modifiable par le propriétaire'; exception when others then raise notice 'PASS  fonds: modification refusée même pour le propriétaire (ajout seul)'; end; end $$;
do $$ begin begin delete from public.audit_log; raise warning 'FAIL audit effaçable'; exception when others then raise notice 'PASS  journal d''audit: effacement refusé'; end; end $$;

-- reversement
select t_fail(u('L1'), format($$select public.reversement(%L,1000,'Espèces')$$,'00000000-0000-0000-0000-0000000000a1'), 'Accès refusé', 'le livreur ne peut pas se déclarer reversé');
select t_fail(u('K'), format($$select public.reversement(%L,99999,'Espèces')$$,'00000000-0000-0000-0000-0000000000a1'), 'Montant invalide', 'reversement supérieur au solde refusé');
select t_as(u('K')); select public.reversement('00000000-0000-0000-0000-0000000000a1',20000,'Espèces','partiel'); select t_root();
select t_ok(t_q(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)::int=10500, 'solde livreur = 10 500 après reversement de 20 000');

-- échec + reprogrammation
select t_as(u('C'));
select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',1500,'paiement','avance','mode','Espèces','confirmer',true,
   'lignes', jsonb_build_array(jsonb_build_object('desig','Cadeau','qte',1,'pu',5000)))))->>'id' as cmd2 \gset
select t_root();
select t_ok((select count(*) from public.fonds where commande_id=:'cmd2' and type='acompte' and montant=6500)=1, 'paiement d''avance -> acompte traçable (6 500)');
select t_as(u('A')); select public.commande_action(:'cmd2','preparer'); select public.commande_action(:'cmd2','prete');
select (public.affecter_livraison(:'cmd2','00000000-0000-0000-0000-0000000000a2'))->>'livraison_id' as liv2 \gset
select t_root();
select t_ok((select montant_attendu from public.livraisons where id=:'liv2')=0, 'commande payée d''avance: 0 F à encaisser');
select t_as(u('L2')); select public.livraison_action(:'liv2','accepter'); select public.livraison_action(:'liv2','echec','{"motif":"Client absent"}'); select t_root();
select t_ok((select statut from public.commandes where id=:'cmd2')='echouee', 'échec -> commande « livraison échouée »');
select t_fail(u('L2'), format($$select public.livraison_action(%L,'echec','{"motif":"x"}')$$,:'liv2'), 'clôturée', 'échec déjà clôturé');
select t_as(u('S')); select public.commande_action(:'cmd2','reprogrammer'); select (public.affecter_livraison(:'cmd2','00000000-0000-0000-0000-0000000000a2'))->>'livraison_id' as liv2b \gset
select t_root();
select t_ok((select tentative from public.livraisons where id=:'liv2b')=2, 'nouvelle tentative comptée séparément (#2)');
select t_fail(u('S'), format($$select public.affecter_livraison(%L,%L,'')$$,:'cmd2','00000000-0000-0000-0000-0000000000a1'), 'Motif de réaffectation obligatoire', 'réaffectation sans motif refusée');
select t_fail(u('S'), format($$select public.corriger_statut(%L,'prete','x')$$,:'cmd2'), 'Accès refusé', 'correction de statut réservée à l''admin');
select t_as(u('A')); select public.corriger_statut(:'cmd2','prete','erreur de saisie'); select t_root();
select t_ok((select count(*) from public.commande_historique where commande_id=:'cmd2' and note like 'CORRECTION%')=1, 'correction exceptionnelle tracée dans l''historique');
select t_fail(u('S'), format($$select public.commande_action(%L,'organiser_retour')$$,:'cmd1'), 'interdite', 'transition interdite livrée -> retour');

-- ================= Vendeurs partenaires =================
select t_as(u('V1'));
select (public.vendeur_deposer_commande(jsonb_build_object('client',jsonb_build_object('nom','Mme Konan','tel','0505 777 777'),'adresse',jsonb_build_object('zone','Abobo','quartier','Anonkoua','repere','Eglise'),
   'lignes',jsonb_build_array(jsonb_build_object('desig','Robe wax','qte',2,'pu',12000)),'pay','livraison')))->>'id' as vc1 \gset
select t_root();
select t_ok((select statut from public.commandes where id=:'vc1')='attente' and (select total from public.commandes where id=:'vc1')=26000 and (select frais from public.commandes where id=:'vc1')=2000, 'commande vendeur: attente, frais Abobo (2 000) fixés par le serveur');
select t_fail(u('V1'), format($$select public.vendeur_deposer_commande(jsonb_build_object('client',jsonb_build_object('nom','X','tel','1'),'adresse',jsonb_build_object('zone','Atlantide','quartier','q'),'lignes',jsonb_build_array(jsonb_build_object('desig','a','qte',1,'pu',1))))$$), 'Zone inconnue', 'zone inconnue refusée');
select t_fail(u('V1'), $$select public.vendeur_deposer_commande(jsonb_build_object('client',jsonb_build_object('nom','X','tel','1'),'adresse',jsonb_build_object('zone','Abobo','quartier','q'),'lignes',jsonb_build_array(jsonb_build_object('desig','a','qte',-1,'pu',1))))$$, 'Articles invalides', 'quantité négative refusée');
select t_ok(t_q(u('V1'),$$select count(*) from public.commandes$$)::int=1, 'vendeur 1 ne voit que sa commande');
select t_ok(t_q(u('V2'),$$select count(*) from public.commandes$$)::int=0, 'vendeur 2 ne voit aucune commande du vendeur 1');
select t_ok(t_q(u('V2'),$$select count(*) from public.clients$$)::int=0, 'vendeur 2 ne voit pas les clients du vendeur 1');
select t_ok(t_q(u('V1'),$$select count(*) from public.livraisons$$)::int=0 and t_q(u('V1'),$$select count(*) from public.fonds$$)::int=0, 'vendeur: ni livraisons ni fonds');
select t_fail(u('V1'), $$select count(*) from public.produits$$, 'x', 'placeholder') where false;
select t_ok(t_q(u('V1'),$$select count(*) from public.produits$$)::int=0, 'vendeur ne voit pas le catalogue interne');
select t_fail(u('V1'), format($$select public.commande_action(%L,'confirmer')$$,:'vc1'), 'Accès refusé', 'le vendeur ne confirme pas sa propre commande');
select t_fail(u('V2'), format($$select public.commande_action(%L,'annuler','test')$$,:'vc1'), 'Commande introuvable|Accès refusé', 'vendeur 2 ne peut pas annuler la commande du vendeur 1');
select t_as(u('S')); select public.commande_action(:'vc1','confirmer'); select t_root();
select t_as(u('A')); select public.commande_action(:'vc1','preparer'); select public.commande_action(:'vc1','prete'); select (public.affecter_livraison(:'vc1','00000000-0000-0000-0000-0000000000a2'))->>'livraison_id' as vl \gset
select t_root();
select code as vcode from public.livraison_codes where livraison_id=:'vl' \gset
select t_as(u('L2')); select public.livraison_action(:'vl','accepter'); select public.livraison_action(:'vl','prise_en_charge','{"nb_colis":1}'); select public.livraison_action(:'vl','demarrer');
select public.livraison_action(:'vl','confirmer',jsonb_build_object('code',:'vcode','montant',26000,'mode','Espèces','recu_par','Konan')); select t_root();
select t_ok((select restant from public.vendeur_dues('00000000-0000-0000-0000-0000000000b1'))=23400, 'vendeur dû: (24 000 articles) x 95 % = 22 800 ? voir ci-dessous') where false;
select t_ok(t_q(u('V1'),$$select restant from public.vendeur_dues()$$)::int=22800, 'vendeur 1: net dû = 24 000 - 5 % = 22 800');
select t_ok(t_q(u('V2'),$$select count(*) from public.vendeur_dues('00000000-0000-0000-0000-0000000000b1')$$)::int=0 or t_q(u('V2'),$$select restant from public.vendeur_dues('00000000-0000-0000-0000-0000000000b1')$$)::int=0, 'vendeur 2 ne lit pas le solde du vendeur 1');
select t_fail(u('K'), format($$select public.regler_vendeur(%L,999999,'Espèces')$$,'00000000-0000-0000-0000-0000000000b1'), 'Montant invalide', 'règlement supérieur au dû refusé');
select t_fail(u('V1'), format($$select public.regler_vendeur(%L,100,'Espèces')$$,'00000000-0000-0000-0000-0000000000b1'), 'Accès refusé', 'le vendeur ne se règle pas lui-même');
select t_as(u('K')); select public.regler_vendeur('00000000-0000-0000-0000-0000000000b1',22800,'Mobile Money','solde'); select t_root();
select t_ok(t_q(u('V1'),$$select restant from public.vendeur_dues()$$)::int=0, 'après règlement: reste 0');
select t_ok(t_q(u('V1'),$$select count(*) from public.reglements_vendeurs$$)::int=1 and t_q(u('V2'),$$select count(*) from public.reglements_vendeurs$$)::int=0, 'chaque vendeur ne voit que ses règlements');

-- ================= Portail client (public) =================
select t_as(u('V1')); select public.creer_lien_portail(a.id,'CMD-X') as tok from public.adresses a join public.clients c on c.id=a.client_id where c.vendeur_id='00000000-0000-0000-0000-0000000000b1' limit 1 \gset
select t_root();
select t_fail(u('V2'), format($$select public.creer_lien_portail(%L)$$,:'ad1'), 'introuvable|Accès refusé', 'vendeur 2 ne crée pas de lien sur une adresse d''autrui');
select t_fail(u('V1'), format($$select public.creer_lien_portail(%L)$$,:'ad1'), 'Accès refusé', 'vendeur 1 ne crée pas de lien sur une adresse de l''ANGEL''S');
select t_anon();
select (public.portail_get(:'tok')) ->> 'org' as o \gset
select (public.portail_poser(:'tok', 5.3101, -4.0123, 12, 'Portail bleu')) as okp \gset
select public.portail_poser('faux-token', 1, 1) as bad \gset
select t_root();
select t_ok(:'o'='ANGEL''S GROUP', 'portail_get sans connexion renvoie le contexte');
select t_ok(:'okp'='t' and :'bad'='f', 'portail_poser: ok avec le bon jeton, false avec un faux');
select t_ok((select lat from public.adresses a join public.clients c on c.id=a.client_id where c.vendeur_id='00000000-0000-0000-0000-0000000000b1' limit 1)=5.3101, 'adresse géolocalisée par le client');
select t_fail(u('V1'), $$select 1$$, 'x', 'placeholder') where false;
select t_anon();
do $$ begin begin perform count(*) from public.commandes; raise warning 'FAIL anon lit commandes'; exception when others then raise notice 'PASS  anon ne lit pas les commandes'; end; end $$;
do $$ begin begin perform public.creer_commande('{}'); raise warning 'FAIL anon appelle creer_commande'; exception when others then raise notice 'PASS  anon ne peut pas appeler creer_commande'; end; end $$;
do $$ begin begin perform public.amorcer_organisation('x', gen_random_uuid(), 'x'); raise warning 'FAIL anon amorce une org'; exception when others then raise notice 'PASS  amorcer_organisation inaccessible à l''API'; end; end $$;
select t_root();
select t_as(u('A'));
do $$ begin begin perform public.amorcer_organisation('x', gen_random_uuid(), 'x'); raise warning 'FAIL admin amorce une org'; exception when others then raise notice 'PASS  amorcer_organisation inaccessible même à l''admin connecté'; end; end $$;
select t_root();

-- ================= Isolation entre sociétés =================
select t_ok(t_q(u('B'),$$select count(*) from public.commandes$$)::int=0 and t_q(u('B'),$$select count(*) from public.clients$$)::int=0 and t_q(u('B'),$$select count(*) from public.fonds$$)::int=0, 'autre société: 0 commande, 0 client, 0 encaissement visibles');
select t_ok(t_q(u('B'),$$select count(*) from public.zones$$)::int=8, 'autre société: ses propres 8 zones seulement');
select t_fail(u('B'), format($$select public.commande_action(%L,'confirmer')$$,:'cmd1'), 'introuvable', 'autre société ne peut pas agir sur nos commandes');
select t_fail(u('B'), format($$select public.affecter_livraison(%L,%L)$$,:'cmd2','00000000-0000-0000-0000-0000000000a1'), 'introuvable', 'autre société ne peut pas affecter nos livreurs');
select t_fail(u('X'), $$select count(*) from public.commandes$$, 'x', 'placeholder') where false;
select t_ok(t_q(u('X'),$$select count(*) from public.commandes$$)::int=0, 'utilisateur sans profil: rien');
select t_fail(u('X'), $$select public.creer_commande('{}')$$, 'Accès refusé', 'utilisateur sans profil: RPC refusée');

-- ================= Direction / lecture seule =================
select t_fail(u('D'), format($$select public.commande_action(%L,'confirmer')$$,:'cmd2'), 'Accès refusé', 'la direction ne modifie rien');
select t_ok(t_q(u('D'),$$select count(*) from public.audit_log$$)::int>10, 'la direction lit le journal d''audit');
select t_fail(u('S'), $$select count(*) from public.audit_log$$, 'x', 'placeholder') where false;
select t_ok(t_q(u('S'),$$select count(*) from public.audit_log$$)::int=0, 'le superviseur ne lit pas l''audit');

-- Purge GPS
insert into public.positions_gps(org_id,livreur_id,lat,lng,ts) values (:'org1','00000000-0000-0000-0000-0000000000a1',5,-4,now()-interval '40 days');
do $$ begin begin delete from public.positions_gps; raise warning 'FAIL gps effaçable à la main'; exception when others then raise notice 'PASS  GPS: effacement manuel refusé'; end; end $$;
select t_ok(app.purge_gps(30)=1, 'purge GPS: supprime uniquement les positions de plus de 30 jours');
select t_ok((select count(*) from public.positions_gps)=1, 'la position récente est conservée');
