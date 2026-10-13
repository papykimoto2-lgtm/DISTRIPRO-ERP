-- Tests du module Caisse. Prérequis : stub + les 24 migrations, base neuve.
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
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','K','D','L1','L2','B','V1']) k;
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


insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',10);
insert into public.membres(user_id,org_id,role,nom,vendeur_id) values (u('V1'),:'org1','vendeur','Aya','00000000-0000-0000-0000-0000000000b1');
create or replace function t_exec(u uuid, q text) returns void language plpgsql as $$ begin perform t_as(u); execute q; perform t_root(); end $$;
grant execute on function t_exec(uuid,text) to public;
-- 1. Création des caisses
select t_as(u('A')); select public.caisse_creer('Caisse principale','571') as cp \gset
select public.caisse_creer('Petite caisse','572') as cq \gset
select t_root();
select t_ok(:'cp' is not null and :'cq' is not null, 'l''administrateur crée la caisse principale et la petite caisse');
select t_fail(u('K'),$$select public.caisse_creer('Autre','571')$$,'Accès|refus|interdit|autoris|droits','un caissier ne crée pas de caisse');
select t_fail(u('A'),$$select public.caisse_creer('Caisse principale','571')$$,'unique|existe|duplicate','nom de caisse en double refusé');
select t_fail(u('A'),$$select public.caisse_creer('X','999')$$,'Compte invalide','compte invalide refusé');
-- 2. Ouverture
select t_fail(u('K'), format($$select public.caisse_mouvement(%L,'entree',1000,'Test','Moi')$$,:'cp'),'Ouvrez la caisse','aucun bon sans caisse ouverte');
select t_as(u('K')); select public.caisse_ouvrir(:'cp',50000) as s1 \gset
select t_root();
select t_ok((select fond_ouverture||'/'||statut from public.caisse_sessions where id=:'s1')='50000/ouverte', 'caisse ouverte avec un fond de 50 000 F');
select t_fail(u('K'), format($$select public.caisse_ouvrir(%L,1000)$$,:'cp'),'déjà ouverte','double ouverture refusée');
select t_fail(u('L1'), format($$select public.caisse_ouvrir(%L,1000)$$,:'cq'),'Accès|refus|interdit|autoris|droits','un livreur n''ouvre pas la caisse');
-- 3. Bons : en attente, numérotation, validation
select t_as(u('K')); select (public.caisse_mouvement(:'cp','entree',20000,'Vente comptoir','Mme Kouassi','R-001','Autre entrée'))->>'id' as m1 \gset
select (public.caisse_mouvement(:'cp','entree',5000,'Avance client','M. Yao',null,'Autre entrée'))->>'id' as m2 \gset
select (public.caisse_mouvement(:'cp','sortie',8000,'Carburant motos','Station Total','F-77','Carburant'))->>'id' as m3 \gset
select t_root();
select t_ok((select numero from public.caisse_mouvements where id=:'m1') ~ '^BE-571-[0-9]{8}-001$', 'numéro d''entrée BE-571-AAAAMMJJ-001');
select t_ok((select numero from public.caisse_mouvements where id=:'m2') ~ '-002$', 'numéro suivant -002');
select t_ok((select numero from public.caisse_mouvements where id=:'m3') ~ '^BS-571-[0-9]{8}-001$', 'numérotation séparée pour les sorties (BS)');
select t_ok((select count(*) from public.caisse_mouvements where session_id=:'s1' and statut='en_attente')=3, 'bons du caissier en attente de validation');
select t_ok(app.caisse_solde_session(:'s1')=50000, 'les bons en attente ne comptent pas dans le solde');
select t_fail(u('K'), format($$select public.caisse_valider(%L,'valider')$$,:'m1'),'Accès|refus|interdit|autoris|droits','le caissier ne valide pas ses propres bons');
select t_fail(u('K'), format($$select public.caisse_mouvement(%L,'sortie',100,'Sans bénéficiaire','')$$,:'cp'),'Bénéficiaire obligatoire','bénéficiaire obligatoire pour une sortie');
select t_fail(u('K'), format($$select public.caisse_mouvement(%L,'entree',100,'Sans déposant',null)$$,:'cp'),'Déposant obligatoire','déposant obligatoire pour une entrée');
select t_fail(u('K'), format($$select public.caisse_mouvement(%L,'entree',0,'Zéro','X')$$,:'cp'),'Montant invalide','montant nul refusé');
select t_exec(u('D'), format($$select public.caisse_valider(%L,'valider')$$,:'m1'));
select t_exec(u('D'), format($$select public.caisse_valider(%L,'valider')$$,:'m3'));
select t_ok(app.caisse_solde_session(:'s1')=50000+20000-8000, 'solde = fond + entrées validées − sorties validées (62 000 F)');
select t_fail(u('D'), format($$select public.caisse_valider(%L,'valider')$$,:'m1'),'déjà traité','un bon déjà traité ne se retraite pas');
select t_fail(u('D'), format($$select public.caisse_valider(%L,'rejeter')$$,:'m2'),'Motif du rejet','rejet sans motif refusé');
select t_exec(u('D'), format($$select public.caisse_valider(%L,'rejeter','Client non identifié')$$,:'m2'));
select t_ok((select statut||'/'||motif_rejet from public.caisse_mouvements where id=:'m2')='rejete/Client non identifié', 'bon rejeté avec motif, sans effet sur le solde');
select t_as(u('K')); select (public.caisse_mouvement(:'cp','sortie',999999,'Trop gros','Fournisseur'))->>'id' as m4 \gset
select t_root();
select t_fail(u('D'), format($$select public.caisse_valider(%L,'valider')$$,:'m4'),'Solde de caisse insuffisant','sortie supérieure au solde refusée à la validation');
select t_exec(u('D'), format($$select public.caisse_valider(%L,'rejeter','Montant erroné')$$,:'m4'));
select t_as(u('A')); select (public.caisse_mouvement(:'cp','entree',3000,'Apport de l''administrateur','Admin'))->>'statut' as sa \gset
select t_root();
select t_ok(:'sa'='valide', 'un bon saisi par l''administrateur est validé d''office');
-- 4. Flux automatiques en espèces
select t_pret() as l1 \gset
select t_conf(:'l1','{"mode":"Espèces"}'::jsonb);
select t_exec(u('K'),$$select public.reversement('00000000-0000-0000-0000-0000000000a1',16000,'Espèces','fin de journée')$$);
select t_ok((select type||'/'||statut||'/'||source||'/'||montant from public.caisse_mouvements where source='reversement')='entree/valide/reversement/16000', 'reversement en espèces : entrée automatique en caisse, validée');
select t_pret() as l2 \gset
select t_conf(:'l2','{"mode":"Espèces"}'::jsonb);
select t_exec(u('K'),$$select public.reversement('00000000-0000-0000-0000-0000000000a1',6000,'Wave','part','WV-CAISSE-1')$$);
select t_ok((select count(*) from public.caisse_mouvements where source='reversement')=1, 'reversement Mobile Money : pas d''écriture de caisse (ce n''est pas du comptant)');
insert into public.paiements_livreurs(org_id,livreur_id,type,montant) values (:'org1','00000000-0000-0000-0000-0000000000a1','commission',2500);
select t_ok((select type||'/'||categorie from public.caisse_mouvements where source='paie')='sortie/Paie livreurs', 'paie d''un livreur : sortie automatique');
insert into public.reglements_vendeurs(org_id,vendeur_id,montant,mode) values (:'org1','00000000-0000-0000-0000-0000000000b1',4000,'Espèces'),(:'org1','00000000-0000-0000-0000-0000000000b1',9000,'Wave');
select t_ok((select count(*) from public.caisse_mouvements where source='reglement_vendeur')=1, 'règlement vendeur : sortie seulement s''il est en espèces');
select t_ok(app.caisse_solde_session(:'s1')=50000+20000-8000+3000+16000-2500-4000, 'solde final de la session cohérent (74 500 F)');
-- 5. Clôture
select t_as(u('K')); select (public.caisse_mouvement(:'cp','sortie',1000,'Petite dépense','Boutique'))->>'id' as m5 \gset
select t_root();
select t_fail(u('K'), format($$select public.caisse_cloturer(%L,74500)$$,:'s1'),'en attente de validation','clôture refusée avec un bon en attente');
select t_exec(u('D'), format($$select public.caisse_valider(%L,'valider')$$,:'m5'));
select t_fail(u('K'), format($$select public.caisse_cloturer(%L,73000)$$,:'s1'),'justification est obligatoire','écart sans justification refusé');
select t_fail(u('K'), format($$select public.caisse_cloturer(%L,-5,'x')$$,:'s1'),'Comptage réel invalide','comptage négatif refusé');
select t_as(u('K')); select public.caisse_cloturer(:'s1',73000,'Billet de 500 F introuvable') as rc \gset
select t_root();
select t_ok(:'rc'::jsonb->>'theorique'='73500' and :'rc'::jsonb->>'ecart'='-500', 'clôture : théorique 73 500, compté 73 000, écart −500 F');
select t_ok((select statut||'/'||ecart_regularise::text from public.caisse_sessions where id=:'s1')='cloturee/false', 'écart non régularisé après clôture');
select t_fail(u('K'), format($$select public.caisse_mouvement(%L,'entree',100,'Après clôture','X')$$,:'cp'),'Ouvrez la caisse','plus de bon sur une session clôturée');
select t_fail(u('K'), format($$select public.caisse_regulariser(%L,'Erreur de comptage corrigée')$$,:'s1'),'Accès|refus|interdit|autoris|droits','le caissier ne régularise pas son propre écart');
select t_fail(u('D'), format($$select public.caisse_regulariser(%L,'ok')$$,:'s1'),'Précisez la décision','décision trop courte refusée');
select t_exec(u('D'), format($$select public.caisse_regulariser(%L,'Manquant imputé au caissier, retenue sur prime')$$,:'s1'));
select t_ok((select ecart_regularise from public.caisse_sessions where id=:'s1'), 'écart régularisé par la direction');
select t_fail(u('D'), format($$select public.caisse_regulariser(%L,'Encore une fois')$$,:'s1'),'Aucun écart','régularisation non rejouable');
-- flux automatique sans caisse ouverte : ignoré, sans erreur
insert into public.paiements_livreurs(org_id,livreur_id,type,montant) values (:'org1','00000000-0000-0000-0000-0000000000a1','avance',1000);
select t_ok((select count(*) from public.caisse_mouvements where source='paie')=1, 'caisse fermée : le flux automatique est ignoré sans bloquer l''opération');
-- 6. Réouverture : continuité du fond
select t_fail(u('K'), format($$select public.caisse_ouvrir(%L,80000)$$,:'cp'),'doit être égal au fond compté','le caissier ne peut pas changer le fond d''ouverture');
select t_as(u('K')); select public.caisse_ouvrir(:'cp') as s2 \gset
select t_root();
select t_ok((select fond_ouverture||'/'||fond_attendu from public.caisse_sessions where id=:'s2')='73000/73000', 'réouverture : fond repris du dernier comptage (73 000 F)');
select t_ok((select count(*) from public.caisse_sessions where caisse_id=:'cp')=2, 'deux sessions pour la caisse principale');
select t_as(u('A')); select public.caisse_cloturer(:'s2',73000) as rc2 \gset
select t_root();
select t_ok((select ecart_regularise from public.caisse_sessions where id=:'s2'), 'clôture sans écart : rien à régulariser');
select t_fail(u('A'), format($$select public.caisse_ouvrir(%L,70000)$$,:'cp'),'Motif obligatoire','l''administrateur doit motiver une modification du fond');
select t_exec(u('A'), format($$select public.caisse_ouvrir(%L,70000,'Dépôt en banque de 3 000 F')$$,:'cp'));
-- 7. Visibilité et écriture directe
select t_ok(t_n(u('K'),'select count(*) from public.caisse_mouvements')>=8, 'le caissier lit les bons');
select t_ok(t_n(u('D'),'select count(*) from public.caisse_sessions')=3, 'la direction lit les sessions');
select t_ok(t_n(u('L1'),'select count(*) from public.caisse_mouvements')=0, 'un livreur ne voit rien');
select t_ok(t_n(u('V1'),'select count(*) from public.caisses')=0, 'un vendeur ne voit rien');
select t_ok(t_n(u('B'),'select count(*) from public.caisse_mouvements')=0, 'une autre société ne voit rien');
select t_fail(u('K'),$$insert into public.caisse_mouvements(org_id,caisse_id,session_id,numero,type,montant,motif) select org_id,caisse_id,id,'X','entree',1,'x' from public.caisse_sessions limit 1$$,'permission|denied','écriture directe interdite');
select t_fail(u('A'),$$update public.caisse_mouvements set montant=1$$,'permission|denied','modification directe interdite');
select t_fail(u('A'),$$delete from public.caisse_mouvements$$,'permission|denied','suppression interdite : un bon se rejette ou se contre-passe');
-- 8. Règlement fournisseur en espèces : seulement depuis une caisse ouverte dont le solde couvre le montant
select t_ok(app.caisse_especes_ok(:'org1', 1000) is null, 'caisse ouverte avec solde suffisant : paiement espèces autorisé');
select t_ok(app.caisse_especes_ok(:'org1', 999999999) like 'Solde de caisse insuffisant%', 'montant supérieur au solde : refusé');
select t_ok(app.caisse_especes_ok(:'org2', 5000) is null, 'autre société sans caisse : règle non appliquée');
select id as sidx, app.caisse_solde_session(id) as sx from public.caisse_sessions where caisse_id=:'cp' and statut='ouverte' \gset
select t_as(u('A')); select public.caisse_cloturer(:'sidx', :sx) \gset
select t_root();
select t_ok(app.caisse_especes_ok(:'org1', 100) like 'Aucune caisse ouverte%', 'caisse fermée : paiement espèces refusé');
