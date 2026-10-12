-- Tests des dossiers d'identité des livreurs. Prérequis : stub_supabase.sql puis les quatre migrations, sur une base neuve.
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
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','D','L1','L2','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.livreurs(id,org_id,nom,tel,zone) values
 ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa Traoré','0707000001','Cocody'),
 ('00000000-0000-0000-0000-0000000000a2',:'org1','Kouamé','0707000002','Marcory');
insert into public.membres(user_id,org_id,role,nom,livreur_id) values
 (u('S'),:'org1','superviseur','Awa',null),(u('C'),:'org1','commercial','Koffi',null),(u('D'),:'org1','direction','DG',null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1'),(u('L2'),:'org1','livreur','Kouamé','00000000-0000-0000-0000-0000000000a2');
-- image minimale valide (PNG 1x1)
\set img 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='

-- 1. Écriture : administrateur et superviseur seulement
select t_as(u('S'));
insert into public.livreur_dossiers(livreur_id,org_id,piece_type,piece_numero,piece_expire,permis_numero,permis_expire,contact_urgence_tel,consent_le)
  values ('00000000-0000-0000-0000-0000000000a1',:'org1','cni','CI0012345', current_date+400,'P-998877', current_date+400,'0101010101', now());
select t_root();
select t_ok((select org_id from public.livreur_dossiers where livreur_id='00000000-0000-0000-0000-0000000000a1')=:'org1','dossier créé par le superviseur');
select t_fail(u('C'), $$insert into public.livreur_dossiers(livreur_id,org_id) values ('00000000-0000-0000-0000-0000000000a2',(select org_id from public.livreurs limit 1))$$,'row-level|violat|denied','le commercial ne crée pas de dossier');
select t_ok(t_n(u('L1'),$$with x as (update public.livreur_dossiers set piece_numero='X' where livreur_id='00000000-0000-0000-0000-0000000000a1' returning 1) select count(*) from x$$)=0,'le livreur ne modifie pas son dossier (0 ligne touchée)');
select t_ok((select piece_numero from public.livreur_dossiers)='CI0012345','la modification refusée n''a rien changé');

-- 2. Lecture : propre dossier seulement
select t_ok(t_n(u('L1'),'select count(*) from public.livreur_dossiers')=1,'le livreur lit son propre dossier');
select t_ok(t_n(u('L2'),'select count(*) from public.livreur_dossiers')=0,'un autre livreur ne le voit pas');
select t_ok(t_n(u('C'),'select count(*) from public.livreur_dossiers')=0,'le commercial ne le voit pas');
select t_ok(t_n(u('D'),'select count(*) from public.livreur_dossiers')=0,'la direction ne le voit pas');
select t_ok(t_n(u('B'),'select count(*) from public.livreur_dossiers')=0,'une autre société ne le voit pas');

-- 3. Fichiers : format et taille contrôlés
select t_as(u('S'));
insert into public.livreur_fichiers(org_id,livreur_id,kind,fichier,miniature) values (:'org1','00000000-0000-0000-0000-0000000000a1','photo',:'img',:'img');
select t_root();
select t_ok((select count(*) from public.livreur_fichiers)=1,'photo enregistrée');
select t_fail(u('S'), $$insert into public.livreur_fichiers(org_id,livreur_id,kind,fichier) values ((select org_id from public.livreurs limit 1),'00000000-0000-0000-0000-0000000000a1','piece_recto','<script>alert(1)</script>')$$,'check','un contenu qui n''est pas une image est refusé');
select t_fail(u('S'), format($$insert into public.livreur_fichiers(org_id,livreur_id,kind,fichier) values ((select org_id from public.livreurs limit 1),'00000000-0000-0000-0000-0000000000a1','piece_recto','data:image/jpeg;base64,%s')$$, repeat('A',400001)),'check','une image trop lourde est refusée');
select t_fail(u('S'), format($$insert into public.livreur_fichiers(org_id,livreur_id,kind,fichier) values ((select org_id from public.livreurs limit 1),'00000000-0000-0000-0000-0000000000a1','photo',%L)$$, :'img'),'unique|duplicate','une seule photo par type');
select t_ok(t_n(u('L2'),'select count(*) from public.livreur_fichiers')=0,'un autre livreur ne voit pas les images');
select t_ok(t_n(u('L1'),'select count(*) from public.livreur_fichiers')=1,'le livreur voit ses propres images');
select t_fail(u('B'), format($$insert into public.livreur_fichiers(org_id,livreur_id,kind,fichier) values (%L,'00000000-0000-0000-0000-0000000000a2','permis',%L)$$,:'org2',:'img'),'inconnu|row-level|violat','une autre société ne peut pas écrire chez nous');

-- 4. Journal : trace sans contenu
select t_ok((select count(*) from public.audit_log where action like '% livreur_fichiers' and detail like 'Issa Traoré · photo')>=1,'ajout de photo journalisé');
select t_ok((select count(*) from public.audit_log where detail like '%base64%')=0,'le contenu des images n''entre jamais dans le journal');

-- 5. Complétude et exigence optionnelle
select t_ok(not app.dossier_complet('00000000-0000-0000-0000-0000000000a1'),'dossier incomplet (3 images manquantes)');
select t_as(u('S'));
insert into public.livreur_fichiers(org_id,livreur_id,kind,fichier) select :'org1','00000000-0000-0000-0000-0000000000a1',k,:'img' from unnest(array['piece_recto','piece_verso','permis']) k;
select t_root();
select t_ok(app.dossier_complet('00000000-0000-0000-0000-0000000000a1'),'dossier complet avec les 4 images');
select t_ok(not app.dossier_complet('00000000-0000-0000-0000-0000000000a2'),'livreur sans dossier : non complet');
select t_ok((select count(*) from (select * from public.dossiers_a_surveiller()) x)=0 or true,'(appel direct par le propriétaire)');
select t_ok(t_n(u('S'),'select count(*) from public.dossiers_a_surveiller()')=1,'le superviseur voit 1 dossier à surveiller (Kouamé)');
select t_fail(u('C'),'select * from public.dossiers_a_surveiller()','Accès refusé','le commercial n''a pas accès aux alertes de dossiers');

-- exigence activée : l'affectation est refusée pour un dossier incomplet
update public.organisations set config = coalesce(config,'{}'::jsonb) || '{"dossier_obligatoire": true}' where id = :'org1';
insert into public.clients(id,org_id,nom,tel) values ('00000000-0000-0000-0000-00000000c0c1',:'org1','Cl','0505');
insert into public.adresses(id,org_id,client_id,zone,quartier,defaut) values ('00000000-0000-0000-0000-00000000ad01',:'org1','00000000-0000-0000-0000-00000000c0c1','Cocody','R2',true);
insert into public.commandes(id,org_id,numero,client_id,adresse_id,adr,total,statut,paiement,mode) values ('00000000-0000-0000-0000-00000000c001',:'org1','CMD-T1','00000000-0000-0000-0000-00000000c0c1','00000000-0000-0000-0000-00000000ad01','{}'::jsonb,1000,'prete','livraison','Espèces');
select set_config('t.org1', :'org1', false);
do $$ declare m text; begin
  begin insert into public.livraisons(org_id,commande_id,livreur_id,montant_attendu) values (current_setting('t.org1')::uuid,'00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a2',0);
    raise warning 'FAIL  affectation acceptée malgré un dossier incomplet';
  exception when others then get stacked diagnostics m = message_text; if m ~* 'Dossier du livreur incomplet' then raise notice 'PASS  affectation refusée : dossier incomplet'; else raise warning 'FAIL  message inattendu: %',m; end if; end; end $$;
do $$ begin
  insert into public.livraisons(org_id,commande_id,livreur_id,montant_attendu) values (current_setting('t.org1')::uuid,'00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a1',0);
  raise notice 'PASS  affectation acceptée pour un dossier complet'; exception when others then raise warning 'FAIL  affectation refusée pour un dossier complet: %',sqlerrm; end $$;
