-- Tests du paiement du client final chez le fournisseur et/ou chez le livreur. Prérequis : stub + les neuf migrations, base neuve.
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
insert into ids select k, gen_random_uuid() from unnest(array['A','S','P','K','L1','V1','V2']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa','0707000001','Cocody');
insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',10),('00000000-0000-0000-0000-0000000000b2',:'org1','Concurrent',0);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) values
 (u('S'),:'org1','superviseur','Awa',null,null),(u('P'),:'org1','preparateur','Moussa',null,null),(u('K'),:'org1','caissier','Yao',null,null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1',null),(u('V1'),:'org1','vendeur','Aya',null,'00000000-0000-0000-0000-0000000000b1'),(u('V2'),:'org1','vendeur','Concurrent',null,'00000000-0000-0000-0000-0000000000b2');
select frais as fr from public.zones where nom='Cocody' \gset
create or replace function t_dep(extra jsonb) returns uuid language plpgsql as $$
declare v uuid; begin perform t_as(u('V1'));
  v := (public.vendeur_deposer_commande(jsonb_build_object('client',jsonb_build_object('nom','Cli','tel','0707123456'),'adresse',jsonb_build_object('zone','Cocody','quartier','Angré','repere',''),
        'lignes',jsonb_build_array(jsonb_build_object('desig','Robe','qte',2,'pu',15000))) || extra))->>'id';
  perform t_root(); return v; end $$;
grant execute on function t_dep(jsonb) to public;
-- 1. Validation
select t_fail(u('V1'), $$select public.vendeur_deposer_commande('{"client":{"nom":"C","tel":"0707"},"adresse":{"zone":"Cocody","quartier":"A"},"lignes":[{"desig":"R","qte":2,"pu":15000}],"pay":"partiel"}'::jsonb)$$, 'montant déjà payé', 'paiement partagé sans montant refusé');
select t_fail(u('V1'), $$select public.vendeur_deposer_commande('{"client":{"nom":"C","tel":"0707"},"adresse":{"zone":"Cocody","quartier":"A"},"lignes":[{"desig":"R","qte":2,"pu":15000}],"pay":"partiel","paye_vendeur":30001}'::jsonb)$$, 'compris entre', 'montant supérieur au prix des articles refusé');
select t_fail(u('V1'), $$select public.vendeur_deposer_commande('{"client":{"nom":"C","tel":"0707"},"adresse":{"zone":"Cocody","quartier":"A"},"lignes":[{"desig":"R","qte":2,"pu":15000}],"pay":"partiel","paye_vendeur":-5}'::jsonb)$$, 'compris entre', 'montant négatif refusé');
-- 2. Trois commandes : tout chez le livreur, partagé, tout chez le fournisseur
select t_dep('{"pay":"livraison"}') as oc \gset
select t_dep('{"pay":"partiel","paye_vendeur":12000}') as oa \gset
select t_dep('{"pay":"paye"}') as ob \gset
select t_ok((select paye_vendeur from public.commandes where id=:'oc')=0 and not (select vendeur_encaisse from public.commandes where id=:'oc'), 'tout chez le livreur : rien payé au vendeur');
select t_ok((select paye_vendeur from public.commandes where id=:'oa')=12000 and not (select vendeur_encaisse from public.commandes where id=:'oa'), 'paiement partagé : 12 000 F payés au vendeur');
select t_ok((select paye_vendeur from public.commandes where id=:'ob')=30000 and (select vendeur_encaisse from public.commandes where id=:'ob'), 'tout chez le vendeur : articles intégralement payés');
select t_ok((select count(*) from public.fonds where commande_id=:'oa' and type='acompte' and mode='Payé au vendeur' and montant=12000)=1, 'le paiement chez le vendeur est tracé (non versé à la caisse du livreur)');
select t_ok((select count(*) from public.fonds where commande_id=:'oc')=0, 'aucun mouvement pour le paiement au livreur avant la livraison');
-- 3. Montant que le livreur devra encaisser
select t_as(u('S')); select public.commande_action(:'oc','confirmer'); select public.commande_action(:'oa','confirmer'); select public.commande_action(:'ob','confirmer'); select t_root();
select t_as(u('P')); select public.commande_action(:'oc','preparer'); select public.commande_action(:'oc','prete'); select public.commande_action(:'oa','preparer'); select public.commande_action(:'oa','prete'); select public.commande_action(:'ob','preparer'); select public.commande_action(:'ob','prete'); select t_root();
select t_as(u('S')); select (public.affecter_livraison(:'oc','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as lc \gset
select t_root();
select t_ok((select montant_attendu from public.livraisons where id=:'lc')=30000+:fr, 'tout au livreur : il encaisse articles + livraison');
select t_as(u('S')); select (public.affecter_livraison(:'oa','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as la \gset
select t_root();
select t_ok((select montant_attendu from public.livraisons where id=:'la')=18000+:fr, 'partagé : il encaisse le reste des articles (18 000) + livraison');
select t_as(u('S')); select (public.affecter_livraison(:'ob','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as lb \gset
select t_root();
select t_ok((select montant_attendu from public.livraisons where id=:'lb')=:fr, 'tout chez le vendeur : il n''encaisse que la livraison');
-- 4. Dû au vendeur avant livraison (en attente)
select t_ok(t_n(u('K'),$$select attente from public.vendeur_dues('00000000-0000-0000-0000-0000000000b1')$$)=27000+16200+0, 'à venir : 27 000 (livraison) + 16 200 (partagé) + 0 (payé chez le vendeur)');
-- 5. Livraisons
create or replace function t_livrer(lid uuid, cmt text) returns void language plpgsql as $$
declare v_code text; v_m int; begin
  select code into v_code from public.livraison_codes where livraison_id = lid;
  select montant_attendu into v_m from public.livraisons where id = lid;
  perform t_as(u('L1'));
  perform public.livreur_consentement();
  perform public.livraison_action(lid,'accepter'); perform public.livraison_action(lid,'prise_en_charge','{"nb_colis":1}'); perform public.livraison_action(lid,'demarrer');
  perform public.livraison_action(lid,'confirmer',jsonb_build_object('code',v_code,'montant',v_m,'mode','Espèces','recu_par','Cli'));
  perform t_root(); end $$;
select t_livrer(:'lc','x'); select t_livrer(:'la','x'); select t_livrer(:'lb','x');
select t_ok((select count(*) from public.commandes where id in (:'oc',:'oa',:'ob') and statut='livree')=3, 'les trois commandes sont livrées');
select t_ok((select count(*) from public.livraisons where id in (:'lc',:'la',:'lb') and ecart=0)=3, 'aucun écart d''encaissement (le livreur a encaissé exactement le dû)');
select t_ok((select sum(montant) from public.fonds where type='encaissement')=(30000+:fr)+(18000+:fr)+:fr, 'la caisse du livreur ne contient que ce qu''il a encaissé');
-- 6. Règlement du vendeur : seulement la part encaissée par ANGEL'S GROUP, moins la commission
select t_ok(t_n(u('K'),$$select acquis from public.vendeur_dues('00000000-0000-0000-0000-0000000000b1')$$)=27000+16200, 'dû au vendeur : 27 000 + 16 200 (rien pour la commande payée chez lui)');
select t_ok(t_n(u('K'),$$select count(*) from public.vendeur_eligibles('00000000-0000-0000-0000-0000000000b1')$$)=2, 'deux commandes entrent dans le règlement (pas la payée chez le vendeur)');
select t_ok(t_n(u('K'),format($$select net from public.vendeur_eligibles('00000000-0000-0000-0000-0000000000b1') where commande_id=%L$$,:'oa'))=16200, 'net de la commande partagée = (30 000 − 12 000) × 90 %');
select t_ok(t_n(u('V1'),'select acquis from public.vendeur_dues()')=43200, 'le vendeur voit le même montant');
select t_ok(t_n(u('V2'),'select acquis from public.vendeur_dues()')=0, 'un autre vendeur ne voit pas ce montant');
select t_as(u('K')); select public.regler_vendeur('00000000-0000-0000-0000-0000000000b1', 43200, 'Virement'); select t_root();
select t_ok(t_n(u('K'),$$select restant from public.vendeur_dues('00000000-0000-0000-0000-0000000000b1')$$)=0, 'règlement complet : reste dû 0');
select t_fail(u('K'), $$select public.regler_vendeur('00000000-0000-0000-0000-0000000000b1', 1, 'Virement')$$, 'dépasse|reste|montant', 'on ne règle pas plus que le dû');
