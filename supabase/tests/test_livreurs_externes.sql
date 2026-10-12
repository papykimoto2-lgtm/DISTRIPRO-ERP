-- Tests des livreurs externes (commission prélevée par ANGEL'S GROUP sur les frais). Prérequis : stub + les 23 migrations, base neuve.
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


update public.livreurs set type='externe', commission_pct=20 where id='00000000-0000-0000-0000-0000000000a1';
-- 1. Livraison par un livreur externe (20 % des frais de 1 500 F prélevés par ANGEL'S GROUP)
select t_pret() as l1 \gset
select t_ok((t_conf(:'l1','{"mode":"Espèces"}'::jsonb))->>'ok'='true', 'livraison confirmée par le livreur externe');
select t_ok((select commission_angels||'/'||part_livreur from public.livraisons where id=:'l1')='300/1200', 'commission d''ANGEL''S 300 F, part du livreur 1 200 F (figées)');
select t_ok(t_n(u('K'),$$select encaisse from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=16000, 'encaissé : 16 000 F');
select t_ok(t_n(u('K'),$$select retenu from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=1200, 'part retenue par le livreur : 1 200 F');
select t_ok(t_n(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=14800, 'restant à reverser : 14 800 F (encaissé moins sa part)');
-- 2. Reversement
select t_fail(u('K'),$$select public.reversement('00000000-0000-0000-0000-0000000000a1',16000,'Espèces','tout')$$,'restant à reverser : 14800','reverser la part du livreur refusé');
select t_as(u('K')); select public.reversement('00000000-0000-0000-0000-0000000000a1',14800,'Espèces','solde'); select t_root();
select t_ok(t_n(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=0, 'après le reversement du net, le solde est nul');
-- 3. Le taux modifié plus tard ne change pas les courses passées
update public.livreurs set commission_pct=50 where id='00000000-0000-0000-0000-0000000000a1';
select t_ok((select commission_angels from public.livraisons where id=:'l1')=300, 'les courses passées gardent leur commission');
select t_pret() as l2 \gset
select t_conf(:'l2','{"mode":"Espèces"}'::jsonb);
select t_ok((select commission_angels||'/'||part_livreur from public.livraisons where id=:'l2')='750/750', 'nouveau taux 50 % appliqué à la course suivante');
update public.livreurs set commission_pct=20 where id='00000000-0000-0000-0000-0000000000a1';
-- 4. Paiement direct sur le compte d'ANGEL'S GROUP : le livreur n'a rien détenu, il ne peut pas retenir sa part
select t_pret() as l3 \gset
select t_conf(:'l3','{"mode":"Orange Money","ref":"OM-EXT-001","direct":true}'::jsonb);
select t_ok((select part_livreur from public.livraisons where id=:'l3')=1200, 'part figée aussi pour une course payée en direct');
select t_ok(t_n(u('K'),$$select retenu from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=1200+750, 'retenue limitée à ce qu''il a détenu (rien sur la course payée en direct)');
-- 5. Livreur interne : aucun changement
select t_ok((select count(*) from public.livraisons where livreur_id='00000000-0000-0000-0000-0000000000a2' and part_livreur is not null)=0, 'pas de part pour un livreur interne');
-- 6. Déclaration Mobile Money : limitée au restant net
select t_pret() as l4 \gset
select t_conf(:'l4','{"mode":"Espèces"}'::jsonb);
select t_ok(t_n(u('K'),$$select solde from public.solde_livreurs() where livreur_id='00000000-0000-0000-0000-0000000000a1'$$)=(16000-750)+(16000-1200), 'restant avant déclaration');
select t_fail(u('L1'),$$select public.declarer_versement(31000,'Wave','WV-EXT-0001')$$,'Montant invalide','déclarer plus que le restant net refusé');
select t_as(u('L1')); select public.declarer_versement(10000,'Wave','WV-EXT-0002') as dv \gset
select t_root();
select t_ok(:'dv' is not null, 'déclaration dans la limite du restant net acceptée');
