-- Tests : entrées de stock, inventaires, journal, état périodique. Prérequis : stub + les six migrations, base neuve.
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
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','K','D','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.membres(user_id,org_id,role,nom) values (u('S'),:'org1','superviseur','Awa'),(u('C'),:'org1','commercial','Koffi'),(u('P'),:'org1','preparateur','Moussa'),(u('K'),:'org1','caissier','Yao'),(u('D'),:'org1','direction','DG');
select t_as(u('A')); insert into public.produits(org_id,code,nom,prix,cout) values (:'org1','P1','Riz 25 kg',14500,11000),(:'org1','P2','Huile 5 L',6500,5000); select t_root();
select id as p1 from public.produits where code='P1' \gset
select id as p2 from public.produits where code='P2' \gset

-- 1. Entrées
select t_fail(u('K'), format($$select public.recevoir_stock(%L, 10, 'BL-1')$$,:'p1'), 'Accès refusé', 'le caissier ne reçoit pas de marchandise');
select t_fail(u('C'), format($$select public.recevoir_stock(%L, 0, 'BL-1')$$,:'p1'), 'invalide', 'quantité nulle refusée');
select t_fail(u('C'), format($$select public.recevoir_stock(%L, 10, '')$$,:'p1'), 'Référence', 'référence obligatoire');
select t_as(u('C')); select public.recevoir_stock(:'p1', 100, 'BL-1001 Fournisseur X', 11500); select public.recevoir_stock(:'p2', 50, 'BL-1002', null); select t_root();
select t_ok((select stock from public.produits where id=:'p1')=100 and (select cout from public.produits where id=:'p1')=11500, 'entrée enregistrée, coût mis à jour');
select t_ok((select count(*) from public.stock_mouvements where type='entree')=2, 'mouvements « entrée » au journal');
-- 2. Ventes simulées (sorties) pour avoir de la matière
select public.ajuster_stock(:'p1', 100, 'x') where false;
select app.stock_mvt(:'org1'::uuid, :'p1'::uuid, -30, 'sortie_commande', 'CMD-T1');
select app.stock_mvt(:'org1'::uuid, :'p1'::uuid, 5, 'retour_stock', 'CMD-T1');
select t_ok((select stock from public.produits where id=:'p1')=75, 'stock 100 - 30 + 5');

-- 3. Inventaire
select t_fail(u('K'), $$select public.ouvrir_inventaire()$$, 'Accès refusé', 'le caissier n''ouvre pas d''inventaire');
select t_as(u('P'));
select public.ouvrir_inventaire('Inventaire de fin de mois') as inv \gset
select t_root();
select t_ok((select count(*) from public.inventaire_lignes where inventaire_id=:'inv')=2, 'une ligne par produit actif');
select t_ok((select numero from public.inventaires where id=:'inv') ~ '^INV-\d{4}-0001$', 'inventaire numéroté');
select t_fail(u('P'), $$select public.ouvrir_inventaire()$$, 'déjà ouvert', 'un seul inventaire ouvert à la fois');
select t_as(u('P')); select public.saisir_comptage(:'inv', :'p1', 70, 'carton abîmé'); select t_root();
select t_fail(u('P'), format($$select public.valider_inventaire(%L)$$,:'inv'), 'Accès refusé', 'le préparateur ne valide pas');
select t_fail(u('A'), format($$select public.valider_inventaire(%L)$$,:'inv'), 'non compté', 'validation refusée tant que tout n''est pas compté');
select t_fail(u('P'), format($$select public.saisir_comptage(%L,%L,-1)$$,:'inv',:'p1'), 'invalide', 'comptage négatif refusé');
select t_as(u('P')); select public.saisir_comptage(:'inv', :'p2', 50); select t_root();
-- une vente survient pendant le comptage
select app.stock_mvt(:'org1'::uuid, :'p2'::uuid, -4, 'sortie_commande', 'CMD-T2');
select t_as(u('A'));
select public.valider_inventaire(:'inv') as res \gset
select t_root();
select t_ok((:'res'::jsonb->>'ecarts')::int=1 and (:'res'::jsonb->>'valeur_ecart')::bigint=-5*11500, 'un écart de -5 valorisé au coût');
select t_ok((select stock from public.produits where id=:'p1')=70, 'stock P1 corrigé à 70');
select t_ok((select stock from public.produits where id=:'p2')=46, 'la vente pendant le comptage est conservée (50 - 4)');
select t_ok((select qte from public.stock_mouvements where type='inventaire')=-5, 'mouvement « inventaire » -5');
select t_fail(u('A'), format($$update public.inventaires set note='x' where id=%L$$,:'inv'), 'permission denied|clos', 'inventaire validé : plus de modification');
select t_fail(u('P'), format($$select public.saisir_comptage(%L,%L,3)$$,:'inv',:'p1'), 'clos', 'plus de comptage sur un inventaire validé');
select t_fail(u('A'), format($$select public.valider_inventaire(%L)$$,:'inv'), 'clos', 'on ne valide pas deux fois');
select t_ok(t_n(u('D'),'select count(*) from public.inventaires')=1, 'la direction lit les inventaires');
select t_ok(t_n(u('K'),'select count(*) from public.inventaires')=0, 'le caissier ne les lit pas');
select t_ok(t_n(u('B'),'select count(*) from public.inventaires')=0, 'une autre société ne les lit pas');
-- annulation
select t_as(u('C'));
select public.ouvrir_inventaire() as inv2 \gset
select t_root();
select t_fail(u('C'), format($$select public.annuler_inventaire(%L,'test')$$,:'inv2'), 'Accès refusé', 'le commercial n''annule pas');
select t_fail(u('A'), format($$select public.annuler_inventaire(%L,'')$$,:'inv2'), 'Motif', 'motif obligatoire');
select t_as(u('A')); select public.annuler_inventaire(:'inv2','erreur de périmètre'); select t_root();
select t_ok((select statut from public.inventaires where id=:'inv2')='annule', 'inventaire annulé');
select t_ok((select count(*) from public.stock_mouvements where type='inventaire')=1, 'aucun mouvement créé par l''annulation');

-- 4. Journal
select t_ok(t_n(u('P'),'select count(*) from public.journal_stock(current_date, current_date)')=6, 'journal du jour : 6 mouvements');
select t_ok(t_n(u('P'),format($$select solde from public.journal_stock(current_date,current_date,%L::uuid) order by id desc limit 1$$,:'p1'))=70, 'solde après le dernier mouvement = stock actuel');
select t_ok(t_n(u('P'),format($$select solde from public.journal_stock(current_date,current_date,%L::uuid) order by id limit 1$$,:'p1'))=100, 'solde après la première entrée = 100');
select t_ok(t_n(u('P'),format($$select count(*) from public.journal_stock(current_date,current_date,null,'entree')$$))=2, 'filtre par type');
select t_fail(u('K'), 'select * from public.journal_stock(current_date,current_date)', 'Accès refusé', 'le caissier ne lit pas le journal');
select t_ok(t_n(u('B'),'select count(*) from public.journal_stock(current_date,current_date)')=0 or true, '(autre société : voir ci-dessous)') where false;
-- 5. État périodique
select t_ok(t_n(u('P'),$$select ouverture from public.etat_stock(current_date,current_date) where code='P1'$$)=0, 'ouverture 0');
select t_ok(t_n(u('P'),$$select cloture from public.etat_stock(current_date,current_date) where code='P1'$$)=70, 'clôture 70');
select t_ok(t_n(u('P'),$$select entrees from public.etat_stock(current_date,current_date) where code='P1'$$)=100, 'entrées 100');
select t_ok(t_n(u('P'),$$select sorties from public.etat_stock(current_date,current_date) where code='P1'$$)=-30, 'sorties -30');
select t_ok(t_n(u('P'),$$select retours from public.etat_stock(current_date,current_date) where code='P1'$$)=5, 'retours +5');
select t_ok(t_n(u('P'),$$select inventaires from public.etat_stock(current_date,current_date) where code='P1'$$)=-5, 'inventaire -5');
select t_ok(t_n(u('P'),$$select count(*) from public.etat_stock(current_date,current_date) where ouverture + entrees + sorties + retours + ajustements + inventaires = cloture$$)=2, 'ouverture + mouvements = clôture (tous les produits)');
select t_ok(t_n(u('P'),$$select ouverture from public.etat_stock(current_date+1,current_date+1) where code='P1'$$)=70 and t_n(u('P'),$$select cloture from public.etat_stock(current_date+1,current_date+1) where code='P1'$$)=70, 'période future : stock stable');
select t_ok(t_n(u('K'),'select count(*) from public.etat_stock(current_date,current_date)')=2, 'le caissier lit l''état des stocks');
select t_fail(u('P'), 'select * from public.etat_stock(current_date,current_date-1)', 'invalide', 'période inversée refusée');
select t_ok(t_n(u('B'),'select count(*) from public.etat_stock(current_date,current_date)')=0, 'une autre société ne voit aucun produit');
select t_ok(t_n(u('B'),'select count(*) from public.journal_stock(current_date,current_date)')=0, 'ni aucun mouvement');
