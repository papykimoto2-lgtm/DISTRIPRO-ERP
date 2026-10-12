-- Tests des versements des livreurs (comptant / Mobile Money). Prérequis : stub + les dix migrations, base neuve.
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

-- 1. Encaissement au comptant
select t_pret() as l1 \gset
select t_ok((t_conf(:'l1','{"mode":"Espèces","ref":"IGNOREE"}'::jsonb))->>'ok'='true', 'livraison payée en espèces');
select t_ok((select ref is null and not direct from public.fonds where livraison_id=:'l1'), 'espèces : pas de référence');
-- 2. Mobile Money : référence obligatoire
select t_pret() as l2 \gset
select code as c2 from public.livraison_codes where livraison_id=:'l2' \gset
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',16000,'mode','Wave','recu_par','C'))$$,:'l2',:'c2'), 'Référence de la transaction', 'Mobile Money sans référence refusé');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',16000,'mode','Wave','ref','ab','recu_par','C'))$$,:'l2',:'c2'), 'Référence de la transaction', 'référence trop courte refusée');
select t_ok((t_conf(:'l2','{"mode":"Wave","ref":"wv12345"}'::jsonb))->>'ok'='true', 'livraison payée par Wave avec référence');
select t_ok((select ref||'/'||direct::text from public.fonds where livraison_id=:'l2')='WV12345/false', 'référence enregistrée en majuscules ; le livreur détient l''argent');
-- 3. Mobile Money direct sur le compte d'ANGEL'S GROUP
select t_pret() as l3 \gset
select t_ok((t_conf(:'l3','{"mode":"Orange Money","ref":"OM99999","direct":true}'::jsonb))->>'ok'='true', 'livraison payée par Orange Money direct sur le compte d''ANGEL''S GROUP');
select t_ok((select direct from public.fonds where livraison_id=:'l3'), 'encaissement marqué « direct »');
select t_ok(t_n(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=32000, 'solde du livreur = 32 000 (espèces + Wave), le direct n''est pas détenu');
select t_ok(t_n(u('K'),$$select encaisse from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=32000, 'encaissé détenu = 32 000');
-- 4. Référence en double
select t_pret() as l4 \gset
select code as c4 from public.livraison_codes where livraison_id=:'l4' \gset
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',16000,'mode','MTN MoMo','ref','WV12345','recu_par','C'))$$,:'l4',:'c4'), 'déjà enregistrée', 'une référence ne sert qu''une fois (même en minuscules/majuscules)');
select t_ok((t_conf(:'l4','{"mode":"Espèces"}'::jsonb))->>'ok'='true', 'encaissement espèces suivant');
select t_ok(t_n(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=48000, 'solde 48 000');
-- 5. Reversement par le caissier
select t_fail(u('K'), $$select public.reversement('00000000-0000-0000-0000-0000000000a1', 1000, 'Wave', '')$$, 'Référence de la transaction', 'versement Mobile Money sans référence refusé');
select t_fail(u('K'), $$select public.reversement('00000000-0000-0000-0000-0000000000a1', 1000, 'Wave', '', 'wv12345')$$, 'déjà enregistrée', 'référence déjà utilisée refusée');
select t_fail(u('K'), $$select public.reversement('00000000-0000-0000-0000-0000000000a1', 48001, 'Espèces', '')$$, 'Montant invalide', 'versement supérieur au dû refusé');
select t_fail(u('L1'), $$select public.reversement('00000000-0000-0000-0000-0000000000a1', 1000, 'Espèces', '')$$, 'Accès refusé', 'le livreur ne s''enregistre pas un versement');
select t_as(u('K')); select public.reversement('00000000-0000-0000-0000-0000000000a1', 16000, 'Espèces', 'remis au bureau'); select t_root();
select t_ok(t_n(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=32000, 'versement comptant : solde 32 000');
-- 6. Déclaration d'un virement Mobile Money par le livreur
select t_fail(u('L1'), $$select public.declarer_versement(10000, 'Espèces', 'AB1234')$$, 'Mobile Money se déclare', 'le comptant ne se déclare pas');
select t_fail(u('L1'), $$select public.declarer_versement(10000, 'Wave', '')$$, 'Référence', 'déclaration sans référence refusée');
select t_fail(u('L1'), $$select public.declarer_versement(10000, 'Wave', 'WV12345')$$, 'déjà enregistrée', 'référence déjà utilisée refusée');
select t_fail(u('L1'), $$select public.declarer_versement(32001, 'Wave', 'WV55555')$$, 'Montant invalide', 'montant supérieur au restant refusé');
select t_fail(u('K'), $$select public.declarer_versement(1000, 'Wave', 'WV55555')$$, 'Accès refusé', 'le caissier ne déclare pas à la place du livreur');
select t_as(u('L1')); select public.declarer_versement(20000, 'Wave', 'wv55555', 'virement 17h') as dv \gset
select t_root();
select t_ok((select statut||'/'||ref from public.versements_declares where id=:'dv')='declare/WV55555', 'versement déclaré, en attente de validation');
select t_ok((select count(*) from public.fonds where type='reversement')=1, 'rien n''est encore compté comme reversé');
select t_fail(u('L1'), $$select public.declarer_versement(12001, 'Wave', 'WV66666')$$, 'Montant invalide', 'on ne déclare pas plus que le restant moins les déclarations en attente');
select t_fail(u('L1'), format($$select public.traiter_versement(%L,'valider')$$,:'dv'), 'Accès refusé', 'le livreur ne valide pas son propre versement');
select t_ok(t_n(u('L1'),'select count(*) from public.versements_declares')=1, 'le livreur voit sa déclaration');
select t_ok(t_n(u('L2'),'select count(*) from public.versements_declares')=0, 'un autre livreur non');
select t_ok(t_n(u('K'),'select count(*) from public.versements_declares')=1, 'le caissier la voit');
select t_ok(t_n(u('C'),'select count(*) from public.versements_declares')=0, 'le commercial non');
select t_fail(u('K'), format($$select public.traiter_versement(%L,'rejeter')$$,:'dv'), 'Motif', 'rejet sans motif refusé');
select t_as(u('K')); select public.traiter_versement(:'dv','valider'); select t_root();
select t_ok((select count(*) from public.fonds where type='reversement' and ref='WV55555' and mode='Wave' and montant=20000)=1, 'validation : reversement enregistré avec la référence');
select t_ok(t_n(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=12000, 'solde 12 000 après validation');
select t_fail(u('K'), format($$select public.traiter_versement(%L,'valider')$$,:'dv'), 'déjà traitée', 'pas de double validation');
-- 7. Rejet puis nouvelle déclaration avec la même référence
select t_as(u('L1')); select public.declarer_versement(5000, 'MTN MoMo', 'MT7777') as dv2 \gset
select t_root();
select t_as(u('K')); select public.traiter_versement(:'dv2','rejeter','SMS de réception introuvable'); select t_root();
select t_ok((select statut||'/'||motif from public.versements_declares where id=:'dv2')='rejete/SMS de réception introuvable', 'versement rejeté avec motif');
select t_as(u('L1')); select public.declarer_versement(5000, 'MTN MoMo', 'MT7777'); select t_root();
select t_ok((select count(*) from public.versements_declares where ref='MT7777')=2, 'une référence rejetée peut être redéclarée');
select t_ok((select count(*) from public.audit_log where action in ('Versement Mobile Money déclaré','Versement Mobile Money validé','Versement Mobile Money rejeté'))>=4, 'déclarations, validations et rejets journalisés');
select t_ok(t_n(u('B'),'select count(*) from public.versements_declares')=0, 'une autre société ne voit rien');
