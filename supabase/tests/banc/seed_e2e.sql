-- Jeu de données du banc d'essai de bout en bout : une société, un compte par profil (mot de passe = « pwd » + identifiant).
\set ON_ERROR_STOP on
create temp table ids(k text primary key, v uuid);
insert into ids select k, gen_random_uuid() from unnest(array['admin','awa','koffi','moussa','yao','dg','issa','kone','aya','rival']) k;
insert into auth.users(id,email,mdp) select v, k||'@users.angels-erp.app', 'pwd'||k from ids;
select public.amorcer_organisation('ANGEL''S GROUP', (select v from ids where k='admin'), 'Administrateur', '0584163232') as org \gset
insert into public.motos(id,org_id,immat,modele,km,prochain_km,statut) values
 ('00000000-0000-0000-0000-0000000000c1',:'org','1234 AB 01','Haojue',14200,15000,'disponible'),
 ('00000000-0000-0000-0000-0000000000c2',:'org','5678 CD 01','Yamaha',22800,23600,'disponible');
insert into public.livreurs(id,org_id,nom,tel,zone,moto_id) values
 ('00000000-0000-0000-0000-0000000000a1',:'org','Issa Traoré','0707000001','Cocody','00000000-0000-0000-0000-0000000000c1'),
 ('00000000-0000-0000-0000-0000000000a2',:'org','Kouamé Yves','0707000002','Marcory','00000000-0000-0000-0000-0000000000c2');
insert into public.vendeurs(id,org_id,nom,tel,commission_pct) values
 ('00000000-0000-0000-0000-0000000000b1',:'org','Aya Boutique','0707555555',5),
 ('00000000-0000-0000-0000-0000000000b2',:'org','Boutique Rivale','0707666666',0);
insert into public.membres(user_id,org_id,role,nom,livreur_id,vendeur_id) select i.v,:'org',r.role,r.nom,r.lid::uuid,r.vid::uuid from ids i join (values
 ('awa','superviseur','Awa (superviseur)',null,null),('koffi','commercial','Koffi (commercial)',null,null),('moussa','preparateur','Moussa (préparateur)',null,null),
 ('yao','caissier','Yao (caissier)',null,null),('dg','direction','Direction',null,null),
 ('issa','livreur','Issa Traoré','00000000-0000-0000-0000-0000000000a1',null),('kone','livreur','Kouamé Yves','00000000-0000-0000-0000-0000000000a2',null),
 ('aya','vendeur','Aya Boutique',null,'00000000-0000-0000-0000-0000000000b1'),('rival','vendeur','Boutique Rivale',null,'00000000-0000-0000-0000-0000000000b2')
) as r(k,role,nom,lid,vid) on r.k=i.k;
insert into public.produits(org_id,code,nom,prix,seuil) values (:'org','P-RIZ','Riz 25 kg',14500,5),(:'org','P-HUI','Huile 5 L',6500,5),(:'org','P-EAU','Eau (pack)',1800,5);
select set_config('request.jwt.claims', json_build_object('sub',(select v from ids where k='admin'))::text, false);
set role authenticated;
select public.ajuster_stock(id, 100, 'init') from public.produits;
reset role;
