-- Tests des tournées, de l'entretien, des documents, des colis étiquetés et de la signature.
-- Prérequis : stub_supabase.sql puis les trois migrations, sur une base neuve.
\set ON_ERROR_STOP on
create or replace function t_as(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u::text,false); execute 'set role authenticated'; end $$;
create or replace function t_root() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub','',false); end $$;
create or replace function t_ok(c boolean, label text) returns void language plpgsql as $$ begin if c then raise notice 'PASS  %',label; else raise warning 'FAIL  %',label; end if; end $$;
create or replace function t_fail(u uuid, q text, frag text, label text) returns void language plpgsql as $$
declare m text; begin perform t_as(u);
  begin execute q; perform t_root(); raise warning 'FAIL  % (aucune erreur)',label;
  exception when others then get stacked diagnostics m = message_text; perform t_root();
    if m ~* frag then raise notice 'PASS  % [%]',label,left(m,70); else raise warning 'FAIL  % (message: %)',label,m; end if; end; end $$;
create or replace function t_q(u uuid, q text) returns text language plpgsql as $$ declare r text; begin perform t_as(u); execute q into r; perform t_root(); return r; exception when others then perform t_root(); raise; end $$;
grant execute on function t_as(uuid), t_root(), t_ok(boolean,text), t_fail(uuid,text,text,text), t_q(uuid,text) to public;

create temp table ids(k text primary key, v uuid);
insert into ids select k, gen_random_uuid() from unnest(array['A','S','C','P','K','D','L1','L2','V1','V2','B']) k;
insert into auth.users(id,email) select v,k||'@t' from ids;
create or replace function u(k text) returns uuid language sql security definer as $$ select v from ids where k=$1 $$;
grant execute on function u(text) to public;
select public.amorcer_organisation('ANGEL''S GROUP', u('A'), 'Admin') as org1 \gset
select public.amorcer_organisation('AUTRE', u('B'), 'Admin B') as org2 \gset
insert into public.motos(id,org_id,immat,modele,km,prochain_km,statut) values
 ('00000000-0000-0000-0000-0000000000c1',:'org1','1111 AA',  'Haojue',1000,1800,'disponible'),
 ('00000000-0000-0000-0000-0000000000c2',:'org1','2222 BB','Yamaha',2000,2800,'panne');
insert into public.livreurs(id,org_id,nom,tel,zone,moto_id) values
 ('00000000-0000-0000-0000-0000000000a1',:'org1','Issa Traoré','0707000001','Cocody','00000000-0000-0000-0000-0000000000c1'),
 ('00000000-0000-0000-0000-0000000000a2',:'org1','Kouamé','0707000002','Marcory','00000000-0000-0000-0000-0000000000c2');
insert into public.vendeurs(id,org_id,nom,commission_pct) values ('00000000-0000-0000-0000-0000000000b1',:'org1','Aya',5),('00000000-0000-0000-0000-0000000000b2',:'org1','Concurrent',0);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) values
 (u('S'),:'org1','superviseur','Awa',null,null),(u('C'),:'org1','commercial','Koffi',null,null),(u('P'),:'org1','preparateur','Moussa',null,null),
 (u('K'),:'org1','caissier','Yao',null,null),(u('D'),:'org1','direction','DG',null,null),
 (u('L1'),:'org1','livreur','Issa','00000000-0000-0000-0000-0000000000a1',null),(u('L2'),:'org1','livreur','Kouamé','00000000-0000-0000-0000-0000000000a2',null),
 (u('V1'),:'org1','vendeur','Aya',null,'00000000-0000-0000-0000-0000000000b1'),(u('V2'),:'org1','vendeur','Concurrent',null,'00000000-0000-0000-0000-0000000000b2');
select t_as(u('A')); insert into public.produits(org_id,code,nom,prix) values (:'org1','P1','Riz 25 kg',14500); select public.ajuster_stock((select id from public.produits where code='P1'),500,'init'); select t_root();
select id as prod from public.produits where code='P1' \gset
select t_as(u('C')); insert into public.clients(org_id,nom,tel) values (:'org1','Boutique Mariam','0505111111'); select t_root();
select id as cl1 from public.clients \gset
select t_as(u('C')); insert into public.adresses(org_id,client_id,zone,quartier,repere,defaut,lat,lng) values (:'org1',:'cl1','Cocody','Riviera 2','Pharmacie',true,5.36,-3.97); select t_root();
select id as ad1 from public.adresses \gset
-- commande prête en une ligne (commercial confirme, préparateur prépare)
create or replace function t_prete(p_qte int, p_frais int default 1500) returns uuid language plpgsql as $$
declare v_cl uuid := (select id from public.clients limit 1); v_ad uuid := (select id from public.adresses limit 1); v_pr uuid := (select id from public.produits limit 1); v_id uuid;
begin
  perform t_as(u('C'));
  v_id := (public.creer_commande(jsonb_build_object('client_id',v_cl,'adresse_id',v_ad,'frais',p_frais,'paiement','livraison','mode','Espèces','confirmer',true,
          'lignes',jsonb_build_array(jsonb_build_object('produit_id',v_pr,'qte',p_qte)))))->>'id';
  perform t_as(u('P')); perform public.commande_action(v_id,'preparer'); perform public.commande_action(v_id,'prete'); perform t_root();
  return v_id; end $$;
grant execute on function t_prete(int,int) to public;

-- ================= 1. Tournées =================
select t_prete(1) as o1 \gset
select t_prete(1) as o2 \gset
select t_prete(1) as o3 \gset
select t_as(u('S')); select (public.creer_tournee('00000000-0000-0000-0000-0000000000a1', array[:'o3',:'o1',:'o2']::uuid[]))->>'tournee_id' as t1 \gset
select t_root();
select t_ok((select numero from public.tournees where id=:'t1')='T-0001', 'tournée numérotée T-0001');
select t_ok((select string_agg(commande_id::text, ',' order by ordre) from public.livraisons where tournee_id=:'t1')=:'o3'||','||:'o1'||','||:'o2', 'ordre de passage respecté (3, 1, 2)');
select t_ok((select count(*) from public.commandes where id in (:'o1',:'o2',:'o3') and statut='affectee')=3, 'les 3 commandes passent « affectée »');
select t_fail(u('L1'), format($$select public.creer_tournee('00000000-0000-0000-0000-0000000000a1', array[%L,%L]::uuid[])$$,:'o1',:'o2'), 'Accès refusé', 'le livreur ne crée pas de tournée');
select t_prete(1) as o4 \gset
select t_fail(u('S'), format($$select public.creer_tournee('00000000-0000-0000-0000-0000000000a1', array[%L,%L]::uuid[])$$,:'o4',:'o1'), 'doit être « prête', 'une commande déjà affectée bloque la tournée');
select t_ok((select statut from public.commandes where id=:'o4')='prete' and (select count(*) from public.tournees)=1, 'tout ou rien : rien n''est créé ni affecté après l''échec');
select t_prete(1) as o5 \gset
select t_fail(u('S'), format($$select public.creer_tournee('00000000-0000-0000-0000-0000000000a2', array[%L,%L]::uuid[])$$,:'o4',:'o5'), 'Moto.*panne', 'moto en panne : tournée refusée');
select t_ok((select count(*) from public.commandes where id in (:'o4',:'o5') and statut='prete')=2 and (select count(*) from public.tournees)=1, 'moto en panne : aucune commande affectée');
select t_fail(u('S'), format($$select public.creer_tournee('00000000-0000-0000-0000-0000000000a1', array[%L]::uuid[])$$,:'o4'), 'au moins 2', 'une seule commande : refusé');
select t_fail(u('S'), format($$select public.creer_tournee('00000000-0000-0000-0000-0000000000a1', array[%L,%L]::uuid[])$$,:'o4',:'o4'), 'deux fois', 'doublon refusé');
select id as lv1 from public.livraisons where tournee_id=:'t1' and ordre=1 \gset
select t_as(u('S')); select public.deplacer_arret(:'lv1', 1); select t_root();
select t_ok((select ordre from public.livraisons where id=:'lv1')=2, 'arrêt déplacé d''un cran vers le bas');
select t_as(u('S')); select public.deplacer_arret(:'lv1', -1); select t_root();
select t_ok((select ordre from public.livraisons where id=:'lv1')=1, 'puis remonté');
select t_as(u('L1')); select public.livraison_action(:'lv1','accepter'); select t_root();
select t_as(u('S')); select public.deplacer_arret(:'lv1', 1); select public.deplacer_arret(:'lv1', -1); select t_root();
select t_ok((select ordre from public.livraisons where id=:'lv1')=1, 'arrêt simplement accepté : encore déplaçable');
select t_as(u('L1')); select public.livraison_action(:'lv1','prise_en_charge','{"nb_colis":1}'); select public.livraison_action(:'lv1','demarrer'); select t_root();
select t_fail(u('S'), format($$select public.deplacer_arret(%L, 1)$$,:'lv1'), 'ordre figé|démarré', 'arrêt démarré : ordre figé');
select t_ok(t_q(u('L1'),$$select count(*) from public.tournees$$)::int=1 and t_q(u('L2'),$$select count(*) from public.tournees$$)::int=0, 'le livreur ne voit que ses tournées');

-- ================= 2. Entretien =================
select t_as(u('S')); select public.enregistrer_entretien('00000000-0000-0000-0000-0000000000c2','2026-10-05','Réparation mécanique',2300,25000,1000,'disponible','Garage Koné'); select t_root();
select t_ok((select km||'/'||prochain_km||'/'||statut from public.motos where id='00000000-0000-0000-0000-0000000000c2')='2300/3300/disponible', 'entretien : km, prochain entretien et statut mis à jour');
select t_ok((select cout from public.entretiens where moto_id='00000000-0000-0000-0000-0000000000c2')=25000, 'coût d''entretien enregistré');
select t_fail(u('S'), $$select public.enregistrer_entretien('00000000-0000-0000-0000-0000000000c1','2026-10-05','Vidange',1000,0,0,'volée','')$$, 'Statut de moto invalide', 'statut de moto invalide refusé');
select t_fail(u('C'), $$select public.enregistrer_entretien('00000000-0000-0000-0000-0000000000c1','2026-10-05','Vidange',1000,0,0,'disponible','')$$, 'Accès refusé', 'le commercial n''enregistre pas d''entretien');
select t_ok(t_q(u('L1'),$$select count(*) from public.entretiens$$)::int=0 and t_q(u('S'),$$select count(*) from public.entretiens$$)::int=1, 'seul le personnel autorisé lit les entretiens');
do $$ begin begin update public.entretiens set cout=1; raise warning 'FAIL entretien modifiable'; exception when others then raise notice 'PASS  entretien en ajout seul'; end; end $$;
select t_as(u('S')); select public.creer_tournee('00000000-0000-0000-0000-0000000000a2', array[:'o4',:'o5']::uuid[]) as t2; select t_root();
select t_ok((select count(*) from public.tournees)=2, 'moto réparée : la tournée du livreur 2 peut maintenant être créée');

-- ================= 3. Documents =================
select t_prete(2) as d1 \gset
select t_as(u('C')); select (public.emettre_document(:'d1','facture'))->>'numero' as f1 \gset
select t_root();
select t_ok(:'f1' ~ '^FAC-20[0-9]{2}-0001$', 'première facture : FAC-aaaa-0001');
select t_ok((select (contenu->>'total')::int from public.documents where numero=:'f1')=30500, 'facture : total 30 500 F (2 × 14 500 + 1 500)');
select t_as(u('C')); select (public.emettre_document(:'d1','facture'))->>'numero' as f1b \gset
select t_root();
select t_ok(:'f1b'=:'f1' and (select count(*) from public.documents where type='facture')=1, 'refaire la facture rouvre la même (pas de nouveau numéro)');
select t_fail(u('C'), format($$select public.emettre_document(%L,'recu')$$,:'d1'), 'Aucun paiement', 'reçu impossible sans paiement');
select t_as(u('C')); select (public.emettre_document(:'d1','bl'))->>'numero' as b1 \gset
select t_root();
select t_ok(:'b1' ~ '^BL-20[0-9]{2}-0001$', 'bon de livraison : BL-aaaa-0001');
select t_as(u('P')); select (public.emettre_document(:'d1','bl'))->>'numero' as b1b \gset
select t_root();
select t_ok(:'b1b'=:'b1', 'le préparateur rouvre le même bon de livraison');
select t_fail(u('P'), format($$select public.emettre_document(%L,'facture')$$,:'d1'), 'Accès refusé', 'le préparateur n''établit pas de facture');
select t_fail(u('L1'), format($$select public.emettre_document(%L,'bl')$$,:'d1'), 'Accès refusé', 'le livreur n''émet aucun document');
select t_fail(u('C'), format($$select public.emettre_document(%L,'avoir','{"facture":"%s","montant":999999,"motif":"x"}')$$,:'d1',(select id from public.documents where numero=:'f1')), 'Montant invalide', 'avoir supérieur à la facture refusé');
select t_fail(u('C'), format($$select public.emettre_document(%L,'avoir',jsonb_build_object('facture',%L,'montant',1000,'motif',''))$$,:'d1',(select id from public.documents where numero=:'f1')), 'Motif obligatoire', 'avoir sans motif refusé');
select t_as(u('K')); select (public.emettre_document(:'d1','avoir',jsonb_build_object('facture',(select id from public.documents where numero=:'f1'),'montant',1000,'motif','Remise commerciale')))->>'numero' as a1 \gset
select t_root();
select t_ok(:'a1' ~ '^AVO-20[0-9]{2}-0001$' and (select ref_doc from public.documents where numero=:'a1')=(select id from public.documents where numero=:'f1'), 'avoir AVO-0001 rattaché à la facture');
select t_fail(u('K'), format($$select public.emettre_document(%L,'avoir',jsonb_build_object('facture',%L,'montant',29501,'motif','trop'))$$,:'d1',(select id from public.documents where numero=:'f1')), 'maximum 29500', 'le cumul des avoirs ne dépasse jamais la facture');
select t_as(u('K')); select public.emettre_document(:'d1','avoir',jsonb_build_object('facture',(select id from public.documents where numero=:'f1'),'montant',29500,'motif','Annulation')); select t_root();
select t_as(u('C')); select (public.emettre_document(:'d1','facture'))->>'numero' as f2 \gset
select t_root();
select t_ok(:'f2' ~ '-0002$', 'facture entièrement annulée par avoirs : une nouvelle facture reçoit le numéro suivant');
do $$ begin begin update public.documents set montant=1; raise warning 'FAIL document modifiable'; exception when others then raise notice 'PASS  document : modification refusée (ajout seul)'; end; end $$;
do $$ begin begin delete from public.documents; raise warning 'FAIL document effaçable'; exception when others then raise notice 'PASS  document : suppression refusée'; end; end $$;
select t_ok((select count(*) from public.documents where type='facture')=2 and (select count(distinct numero) from public.documents)=(select count(*) from public.documents), 'numéros tous distincts, séquence sans trou');
select t_ok(t_q(u('L1'),$$select count(*) from public.documents$$)::int=0 and t_q(u('V1'),$$select count(*) from public.documents$$)::int=0, 'livreur et vendeur ne lisent aucun document');
select t_ok(t_q(u('P'),$$select count(*) from public.documents$$)::int=1 and t_q(u('P'),$$select count(*) from public.documents where type<>'bl'$$)::int=0, 'préparateur : uniquement les bons de livraison');
select t_ok(t_q(u('D'),$$select count(*) from public.documents$$)::int=(select count(*) from public.documents) and t_q(u('B'),$$select count(*) from public.documents$$)::int=0, 'direction lit tout ; autre société ne voit rien');
-- paiement + reçu
select t_as(u('C')); select (public.creer_commande(jsonb_build_object('client_id',:'cl1','adresse_id',:'ad1','frais',1500,'paiement','avance','mode','Mobile Money','confirmer',true,'lignes',jsonb_build_array(jsonb_build_object('desig','Cadeau','qte',1,'pu',5000)))))->>'id' as d2 \gset
select (public.emettre_document(:'d2','recu'))->>'numero' as r1 \gset
select (public.emettre_document(:'d2','recu'))->>'numero' as r1b \gset
select t_root();
select t_ok(:'r1' ~ '^REC-20[0-9]{2}-0001$' and :'r1b'=:'r1', 'reçu REC-0001, réutilisé tant que le total payé ne change pas');
select t_fail(u('C'), format($$select public.emettre_document(%L,'bl')$$,:'d2'), 'impossible dans cet état', 'bon de livraison impossible avant la préparation');
-- facture d'une commande de vendeur : frais seuls, au nom du vendeur
select t_as(u('V1')); select (public.vendeur_deposer_commande(jsonb_build_object('client',jsonb_build_object('nom','Mme Konan','tel','0505777777'),'adresse',jsonb_build_object('zone','Abobo','quartier','Anonkoua'),'lignes',jsonb_build_array(jsonb_build_object('desig','Robe','qte',2,'pu',12000)),'pay','livraison')))->>'id' as vc1 \gset
select t_root();
select t_as(u('S')); select public.commande_action(:'vc1','confirmer'); select (public.emettre_document(:'vc1','facture'))->>'numero' as vf \gset
select t_root();
select t_ok((select client->>'nom' from public.documents where numero=:'vf')='Aya' and (select (contenu->>'total')::int from public.documents where numero=:'vf')=2000 and (select jsonb_array_length(contenu->'lignes') from public.documents where numero=:'vf')=1, 'facture d''une commande de vendeur : frais de livraison seuls, au nom du vendeur');

-- ================= 4. Colis étiquetés =================
select t_prete(1) as e1 \gset
select t_fail(u('L1'), format($$select public.etiqueter_commande(%L,2)$$,:'e1'), 'Accès refusé', 'le livreur n''imprime pas d''étiquettes');
select t_fail(u('P'), format($$select public.etiqueter_commande(%L,0)$$,:'e1'), 'invalide', 'nombre de colis invalide');
select t_as(u('P')); select public.etiqueter_commande(:'e1',2); select t_root();
select t_ok((select nb_colis from public.commandes where id=:'e1')=2 and (select count(*) from public.colis where commande_id=:'e1')=2, 'deux colis étiquetés');
select tok as tok1 from public.colis where commande_id=:'e1' and n=1 \gset
select tok as tok2 from public.colis where commande_id=:'e1' and n=2 \gset
select numero as enum from public.commandes where id=:'e1' \gset
select t_ok(:'tok1' ~ '^[A-HJ-NP-Z2-9]{5}$' and :'tok1'<>:'tok2', 'codes de 5 caractères sans ambiguïté, distincts');
select t_as(u('P')); select public.etiqueter_commande(:'e1',2) as same; select t_root();
select t_ok((select tok from public.colis where commande_id=:'e1' and n=1)=:'tok1', 'réimpression : mêmes codes');
select t_as(u('S')); select (public.affecter_livraison(:'e1','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as el \gset
select t_root();
select t_ok(t_q(u('L1'),$$select count(*) from public.colis$$)::int=0, 'le livreur ne lit pas les codes des colis');
select t_ok(t_q(u('L1'),format($$select nb_colis from public.commandes where id=%L$$,:'e1'))::int=2, 'mais il voit que la commande a 2 étiquettes');
select t_ok(t_q(u('P'),format($$select (public.verifier_colis(%L,%L))->>'ok'$$,:'e1','AGE1|'||:'enum'||'|1/2|'||:'tok1'))='true', 'personnel : vérification possible');
select t_ok(t_q(u('L1'),format($$select (public.verifier_colis(%L,%L))->>'ok'$$,:'e1','AGE1|'||:'enum'||'|1/2|'||:'tok1'))='true', 'livreur : QR du colis 1 reconnu');
select t_ok(t_q(u('L1'),format($$select (public.verifier_colis(%L,%L))->>'mode'$$,:'e1',lower(:'tok2')))='saisie', 'livreur : code court reconnu (mode « saisie »)');
select t_ok(t_q(u('L1'),format($$select (public.verifier_colis(%L,%L))->>'msg'$$,:'e1','AGE1|'||:'enum'||'|1/2|ZZZZZ')) like 'Étiquette invalide%', 'livreur : étiquette falsifiée refusée');
select t_ok(t_q(u('L1'),format($$select (public.verifier_colis(%L,%L))->>'msg'$$,:'e1','AGE1|CMD-2026-9999|1/1|AAAAA')) like 'Ce colis appartient à la commande CMD-2026-9999%', 'livreur : colis d''une autre commande refusé');
select t_ok(t_q(u('L1'),format($$select (public.verifier_colis(%L,%L))->>'ok'$$,:'e1','bonjour'))='false', 'livreur : texte quelconque refusé');
select t_fail(u('L2'), format($$select public.verifier_colis(%L,'AAAAA')$$,:'e1'), 'Accès refusé', 'un autre livreur ne peut pas sonder les codes');
-- parcours livreur avec scans
select t_as(u('L1')); select public.livraison_action(:'el','accepter'); select t_root();
select t_fail(u('L1'), format($$select public.livraison_action(%L,'prise_en_charge','{"nb_colis":2}')$$,:'el'), 'Scannez les colis', 'prise en charge sans scan refusée même avec un nombre déclaré');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'prise_en_charge',jsonb_build_object('scans',jsonb_build_array(%L)))$$,:'el','AGE1|'||:'enum'||'|1/2|'||:'tok1'), 'Il reste 1 colis', 'un colis sur deux : refusé');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'prise_en_charge',jsonb_build_object('scans',jsonb_build_array(%L,%L)))$$,:'el','AGE1|'||:'enum'||'|1/2|'||:'tok1','AGE1|'||:'enum'||'|2/2|ZZZZZ'), 'invalide', 'un faux QR dans le lot : refusé');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'prise_en_charge',jsonb_build_object('scans',jsonb_build_array(%L,%L)))$$,:'el','AGE1|'||:'enum'||'|1/2|'||:'tok1','AGE1|'||:'enum'||'|1/2|'||:'tok1'), 'Il reste 1 colis', 'le même colis scanné deux fois ne compte qu''une fois');
select t_as(u('L1')); select public.livraison_action(:'el','prise_en_charge',jsonb_build_object('scans',jsonb_build_array('AGE1|'||:'enum'||'|1/2|'||:'tok1', :'tok2'),'etat','Bon état')); select t_root();
select t_ok((select nb_colis||'/'||jsonb_array_length(colis_scans)||'/'||(colis_scans->1->>'mode') from public.livraisons where id=:'el')='2/2/saisie', 'prise en charge : 2 colis, dont un saisi à la main (tracé)');
select t_fail(u('S'), format($$select public.etiqueter_commande(%L,3)$$,:'e1'), 'déjà été scannés', 'nombre de colis figé une fois scanné');
select t_as(u('L1')); select public.livraison_action(:'el','demarrer'); select t_root();
select code as ecode from public.livraison_codes where livraison_id=:'el' \gset
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',16000,'mode','Espèces','recu_par','M'))$$,:'el',:'ecode'), 'Scannez les colis', 'remise sans scan des colis refusée');
select t_as(u('L1')); select public.livraison_action(:'el','confirmer',jsonb_build_object('code',:'ecode','montant',16000,'mode','Espèces','recu_par','Mariam','scans',jsonb_build_array(:'tok1',:'tok2'))); select t_root();
select t_ok((select statut||'/'||jsonb_array_length(colis_liv) from public.livraisons where id=:'el')='livree/2', 'remise confirmée avec les 2 colis scannés');
-- réglage : scan désactivé
update public.organisations set config = config || '{"etiq_scan":false}'::jsonb where id=:'org1';
select t_prete(1) as e2 \gset
select t_as(u('P')); select public.etiqueter_commande(:'e2',1); select t_root();
select t_as(u('S')); select (public.affecter_livraison(:'e2','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as el2 \gset
select t_root();
select t_as(u('L1')); select public.livraison_action(:'el2','accepter'); select public.livraison_action(:'el2','prise_en_charge','{"nb_colis":1}'); select t_root();
select t_ok((select nb_colis from public.livraisons where id=:'el2')=1, 'scan désactivé dans les réglages : prise en charge sans scan acceptée');
update public.organisations set config = config - 'etiq_scan' where id=:'org1';

-- ================= 5. Signature =================
select t_prete(8) as g1 \gset
select t_as(u('S')); select (public.affecter_livraison(:'g1','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as gl \gset
select t_root();
select t_as(u('L1')); select public.livraison_action(:'gl','accepter'); select public.livraison_action(:'gl','prise_en_charge','{"nb_colis":1}'); select public.livraison_action(:'gl','demarrer'); select t_root();
select code as gcode from public.livraison_codes where livraison_id=:'gl' \gset
select t_ok((select total from public.commandes where id=:'g1')=117500, 'commande de 117 500 F (au-dessus du seuil de 100 000 F)');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',117500,'mode','Espèces','recu_par','M'))$$,:'gl',:'gcode'), 'Signature du destinataire obligatoire', 'signature exigée au-dessus du seuil');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',117500,'mode','Espèces','recu_par','M','signature','http://evil/x.png'))$$,:'gl',:'gcode'), 'Signature invalide', 'signature qui n''est pas une image PNG intégrée : refusée');
select t_fail(u('L1'), format($$select public.livraison_action(%L,'confirmer',jsonb_build_object('code',%L,'montant',117500,'mode','Espèces','recu_par','M','signature','data:image/png;base64,'||repeat('A',90000)))$$,:'gl',:'gcode'), 'Signature invalide', 'signature trop volumineuse : refusée');
select t_as(u('L1')); select public.livraison_action(:'gl','confirmer',jsonb_build_object('code',:'gcode','montant',117500,'mode','Espèces','recu_par','M','signature','data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==')); select t_root();
select t_ok((select signature is not null from public.livraisons where id=:'gl'), 'signature valide enregistrée');
select t_ok(t_q(u('S'),format($$select (signature is not null)::text from public.livraisons where id=%L$$,:'gl'))='true', 'le superviseur peut lire la signature (bon de livraison)');
-- sous le seuil : facultative
select t_ok((select count(*) from public.livraisons where signature is null and statut='livree')>=1, 'sous le seuil : livraison sans signature acceptée');

-- ================= 6. Lectures calculées =================
select t_ok((select paye from public.soldes_commandes() where commande_id=:'d2')=0 or true, 'soldes_commandes : appelable') where false;
select t_as(u('K')); select paye as p_d2 from public.soldes_commandes() where commande_id=:'d2' \gset
select t_root();
select t_ok(:'p_d2'::int=6500, 'soldes_commandes : acompte de 6 500 F (commande payée d''avance)');
select t_ok((select count(*) from public.soldes_commandes() where false)=0, 'ok') where false;
-- vendeur : livraison complète d'une commande de vendeur
select t_as(u('P')); select public.commande_action(:'vc1','preparer'); select public.commande_action(:'vc1','prete'); select t_root();
select t_as(u('S')); select (public.affecter_livraison(:'vc1','00000000-0000-0000-0000-0000000000a1'))->>'livraison_id' as vl \gset
select t_root();
select code as vcode from public.livraison_codes where livraison_id=:'vl' \gset
select t_as(u('L1')); select public.livraison_action(:'vl','accepter'); select public.livraison_action(:'vl','prise_en_charge','{"nb_colis":1}'); select public.livraison_action(:'vl','demarrer');
select public.livraison_action(:'vl','confirmer',jsonb_build_object('code',:'vcode','montant',26000,'mode','Espèces','recu_par','Konan')); select t_root();
select t_ok(t_q(u('V1'),$$select count(*) from public.vendeur_eligibles()$$)::int=1 and t_q(u('V1'),$$select net from public.vendeur_eligibles()$$)::int=22800, 'vendeur : commande éligible, net 22 800 F (24 000 − 5 %)');
select t_ok(t_q(u('V1'),$$select restant from public.vendeur_dues()$$)::int=22800, 'cohérent avec le montant dû');
select t_ok(t_q(u('V2'),$$select count(*) from public.vendeur_eligibles()$$)::int=0 and t_q(u('V2'),format($$select count(*) from public.vendeur_eligibles(%L)$$,'00000000-0000-0000-0000-0000000000b1'))::int=0, 'un autre vendeur ne voit rien de ce vendeur');
select t_ok(t_q(u('V1'),format($$select paye from public.soldes_commandes() where commande_id=%L$$,:'vc1'))::int=26000, 'le vendeur voit le payé de sa commande (sans lire les fonds)');
select t_ok(t_q(u('V2'),$$select count(*) from public.soldes_commandes()$$)::int=0, 'un autre vendeur : aucune commande');
select t_ok(t_q(u('B'),$$select count(*) from public.soldes_commandes()$$)::int=0, 'autre société : aucune commande');
select t_fail(u('L1'), $$select * from public.vendeur_eligibles()$$, 'Accès refusé', 'le livreur ne lit pas les montants dus aux vendeurs');
