# Backend Supabase d'ANGEL'S GROUP ERP

Projet **dédié** à ce logiciel (ne pas le mélanger avec les autres applications de l'organisation).

## Contenu
| Fichier | Rôle |
|---|---|
| `migrations/20261010000000_angels_erp_schema.sql` | 25 tables, RLS, machine à états des commandes, journaux « ajout seul », 22 fonctions RPC (+ 1 d'amorçage) |
| `functions/creer-utilisateur/index.ts` | Edge Function admin : crée compte + profil (livreur, vendeur, personnel) |
| `migrations/20261011000000_notifications.sql` | File de notifications clients, modèles de messages, réservation et reprises d'envoi, accusés de réception |
| `functions/envoyer-notifications`, `functions/messagerie-webhook`, `functions/_shared/messagerie.ts` | **Envoi automatique** WhatsApp / SMS (Twilio ou WhatsApp Cloud) — voir `MESSAGERIE.md` |
| `tests/` | 84 vérifications de sécurité/règles métier + 43 sur les notifications (SQL) + 14 sur la logique d'envoi (Node) |

## Mise en route
1. Créer le projet Supabase (région proche d'Abidjan : `eu-west-3`).
2. **Authentication → Providers → Email** : désactiver « Allow new users to sign up » (les comptes sont créés uniquement par l'administrateur).
3. Appliquer la migration (SQL Editor, `supabase db push`, ou l'outil MCP `apply_migration`).
4. Créer le premier utilisateur dans **Authentication → Users**, puis, dans le SQL Editor :
   ```sql
   select public.amorcer_organisation('ANGEL''S GROUP', '<uuid-de-l-utilisateur>', 'Administrateur', '0584163232');
   ```
   (crée l'organisation, le profil administrateur, les 8 zones et les listes par défaut ; fonction non accessible depuis l'API).
5. Déployer la fonction : `supabase functions deploy creer-utilisateur`.
6. Planifier la purge GPS (rétention 30 jours) si `pg_cron` est activé :
   `select cron.schedule('purge-gps', '0 3 * * *', $$select app.purge_gps(30)$$);`
7. Lancer les **advisors** de sécurité Supabase. Les alertes « SECURITY DEFINER exécutable par authenticated » sur les fonctions `public.*` sont **attendues** : chacune contrôle le profil de l'appelant en première ligne.

## Principes de sécurité
- Toutes les tables ont `org_id` + RLS : une société ne voit jamais les données d'une autre.
- **Aucune écriture métier directe** sur commandes, livraisons, fonds, stock, règlements : uniquement via RPC qui vérifient profil, état et montants (totaux recalculés côté serveur, frais de vendeur fixés par la zone).
- Le **code de confirmation** est dans une table que ni le livreur ni le vendeur ne peuvent lire ; 5 essais maximum.
- Un **reversement** ou un **règlement vendeur** ne peut être enregistré que par le caissier/administrateur, et jamais au-delà du solde.
- `fonds`, `audit_log`, `commande_historique`, `positions_gps`, `stock_mouvements` sont en **ajout seul** (même le propriétaire ne peut pas les modifier).
- GPS : enregistré uniquement pendant une course en cours, après consentement ; lecture réservée au superviseur, à l'administrateur et à la direction.
- Portail client : jetons aléatoires de 244 bits, valables 30 jours, 10 envois maximum, accessibles sans compte uniquement via `portail_get` / `portail_poser`.

## Tests
Les tests tournent sur un PostgreSQL local avec de faux rôles Supabase :
```bash
psql -d test -f supabase/tests/stub_supabase.sql
psql -d test -f supabase/migrations/20261010000000_angels_erp_schema.sql
psql -d test -f supabase/migrations/20261011000000_notifications.sql
psql -d test -f supabase/tests/test_securite.sql      # affiche PASS / FAIL pour chaque règle
# (base neuve pour chaque fichier de test) psql -d test2 ... -f supabase/tests/test_notifications.sql
```
Ils couvrent : isolation entre sociétés, vendeurs et livreurs ; statuts et stock non modifiables en direct ; double validation ; écarts ; reversements ; règlements vendeurs ; portail public ; journaux inviolables ; purge GPS.

## Brancher l'application HTML (fait)
`index.html` embarque un **mode connecté** : tant que l'adresse et la clé ne sont pas renseignées, l'application reste en mode démonstration (données dans le navigateur).

1. Projet Supabase créé, les 3 migrations (`supabase/migrations/`) appliquées, premier administrateur créé et `amorcer_organisation` exécutée (voir « Mise en route »).
2. Appliquer aussi `20261013000000_dossiers_livreurs.sql` (dossiers d'identité des livreurs).
2b. Déployer les trois fonctions : `creer-utilisateur`, `envoyer-notifications`, `messagerie-webhook` (secrets : voir `MESSAGERIE.md`).
3. Dans `index.html`, renseigner la constante (clé **publishable** uniquement, jamais la clé `service_role`) :
   ```js
   const CLOUD_DEFAULT={url:"https://<projet>.supabase.co",key:"sb_publishable_..."};
   ```
   (ou, sans modifier le fichier, définir `window.ANGELS_CLOUD={url,key}` avant le script).
4. Servir la page en **https** (Vercel) : GPS, caméra (QR) et sessions l'exigent. La bibliothèque `supabase-js` est chargée depuis jsDelivr avec empreinte SRI.
5. Les identifiants saisis à l'écran (ex. `awa`) deviennent `awa@users.angels-erp.app` côté Supabase Auth ; le code secret fait au moins 6 caractères en mode connecté. L'administrateur crée les comptes dans l'écran *Utilisateurs / Livreurs / Vendeurs* (fonction `creer-utilisateur`).

Certains profils ne lisent pas toutes les tables (ex. un préparateur ne lit pas les fiches clients, un commercial ne lit pas les livreurs) : l'écran affiche alors « Client » / « Livreur » à la place du nom.

### Banc d'essai de bout en bout
`tests/banc/` contient une passerelle (`gateway.mjs`, fausse authentification + fonction de création de compte) à placer devant un vrai PostgREST et la base de test chargée avec `seed_e2e.sql` ; `tests/banc/e2e_*.js` pilotent l'application dans Chromium (Playwright) pour chaque profil : cycle complet d'une commande (création, préparation, étiquettes, affectation, scans, code de livraison, signature, reversement), toutes les pages de chaque profil, dépôt/import vendeur, isolation entre vendeurs, paramètres, documents, entretien, création de compte, portail client.

### Dossiers d'identité des livreurs
Migration `20261013000000_dossiers_livreurs.sql` : état civil, pièce d'identité, permis, contacts, accord du livreur (`livreur_dossiers`) et 4 images par livreur — photo, pièce recto/verso, permis (`livreur_fichiers`, JPEG/PNG en data-URL, 400 Ko max, miniature de 20 Ko pour les listes). Lecture et écriture : administrateur et superviseur seulement ; le livreur lit son propre dossier ; le journal trace l'action sans jamais contenir l'image. `app.dossier_complet()` et `public.dossiers_a_surveiller()` (échéances à 30 jours). Option `dossier_obligatoire` (Paramètres) : le serveur refuse alors toute affectation à un livreur au dossier incomplet ou expiré. Tests : `tests/test_dossiers.sql`, `tests/banc/e2e_dossiers*.js`.

### Suivi client et avis
Migration `20261014000000_suivi_client.sql` : `suivi_liens` (un jeton de 256 bits par commande, 30 jours, aucune politique d'accès : uniquement via les fonctions), `avis_livraison` (1 à 5 étoiles, ajout seul, lisible par administrateur, superviseur, direction et le livreur concerné). Fonctions : `creer_lien_suivi` (administrateur, superviseur, commercial, vendeur propriétaire), `suivi_get` et `suivi_noter` (publiques, par jeton). La page publique ne révèle ni le code de livraison, ni le nom de famille ou le téléphone du livreur ; la position n'est donnée que pendant la course (15 minutes de fraîcheur). Tests : `tests/test_suivi.sql`, `tests/banc/e2e_suivi*.js`.

### Journal, inventaire, états périodiques
Migration `20261015000000_inventaire_etats.sql` : colonne `produits.cout`, `recevoir_stock` (entrée avec référence obligatoire), `inventaires` / `inventaire_lignes` (un seul inventaire ouvert, figé une fois validé ou annulé), `ouvrir_inventaire`, `saisir_comptage`, `valider_inventaire` (administrateur ; tout compté ; écart contre le stock relevé à l'ouverture ; mouvement `inventaire` par écart), `annuler_inventaire`, `journal_stock` (avec stock après chaque mouvement) et `etat_stock` (ouverture, entrées, sorties, retours, ajustements, inventaire, clôture par produit). Tests : `tests/test_inventaire.sql`, `tests/banc/e2e_inventaire*.js`.

### Photos de commande (saisie WhatsApp)
Migration `20261016000000_photos_commandes.sql` : `commande_photos` (JPEG/PNG 300 Ko max, 8 par commande), `ajouter_photo_commande` / `retirer_photo_commande` (équipe commerciale ou vendeur propriétaire ; commande non terminée), lecture par l'équipe, le préparateur, le vendeur propriétaire et le livreur de la mission. Tests : `tests/test_photos.sql`, `tests/banc/e2e_whatsapp*.js`, `e2e_partage.js`.

### Collectes chez les vendeurs
Migration `20261017000000_collectes.sql` : `vendeurs.adresse_collecte`, `collectes` (planifiée → acceptée → en route → collectée → réceptionnée ; non réalisée / annulée), `collecte_codes` (code lisible par le vendeur et le superviseur, jamais par le livreur), `collecte_commandes` (colis collectés / reçus, résumé des articles). Fonctions : `maj_adresse_collecte`, `planifier_collecte` (administrateur, superviseur ; commandes confirmées du vendeur, pas déjà en collecte ; dossier du livreur contrôlé si l'option est active), `collecte_action` (accepter, refuser, partir, collecter avec code et 5 essais, recevoir par le préparateur ou l'administrateur — les commandes complètes passent en préparation —, reaffecter, annuler, echec). Tests : `tests/test_collectes.sql`, `tests/banc/e2e_collectes*.js`.

### Paiement chez le fournisseur et/ou chez le livreur
Migration `20261018000000_paiement_vendeur.sql` : `commandes.paye_vendeur` (part des articles payée directement au vendeur, reprise de l'ancien indicateur `vendeur_encaisse`), `vendeur_deposer_commande` (`pay` = livraison | partiel + `paye_vendeur` | paye ; contrôle 0 ≤ montant ≤ prix des articles ; le paiement chez le vendeur est tracé en `fonds` mode « Payé au vendeur »), `vendeur_dues` et `vendeur_eligibles` (net = (articles − payé chez le vendeur) × (1 − commission), sur la seule part encaissée par ANGEL'S GROUP). Tests : `tests/test_paiement_vendeur.sql`, `tests/banc/e2e_paiement*.js`.

### Incidents automatiques à la réception d'une collecte
Migration `20261019000000_collecte_incidents.sql` : `app.incident_auto` et nouvelle version de `collecte_action` — à la réception, un incident est ouvert pour chaque commande en écart (« Colis manquant » : manquants ou commande non remise ; « Écart de colis » : colis en trop) ; la réponse indique le nombre d'incidents ouverts. Tests : `tests/test_collectes.sql` (section 8), `tests/banc/e2e_collecte_incidents*.js`.

### Versements des livreurs (comptant / Mobile Money)
Migration `20261020000000_versements_mobile_money.sql` : `fonds.ref` (référence de transaction, unique par société, insensible à la casse) et `fonds.direct` (payé directement sur le compte d'ANGEL'S GROUP : non détenu par le livreur, exclu de son solde), `app.est_mobile`, `livraison_action` (Mobile Money : référence obligatoire, 4 caractères minimum, jamais réutilisable), `reversement` (+ `p_ref`), `solde_livreurs`, table `versements_declares` et fonctions `declarer_versement` (livreur ; Mobile Money seulement ; montant ≤ restant dû − déclarations en attente) et `traiter_versement` (caissier / administrateur : valider crée le reversement avec la référence, rejeter exige un motif). Tests : `tests/test_versements.sql`, `tests/banc/e2e_versements*.js`.

### Commande passée par le client (lien du fournisseur)
Migration `20261021000000_commande_client.sql` : tables `commande_liens` (jeton secret par fournisseur, aucune politique d'accès direct) et `demandes_commande` (lecture réservée au fournisseur concerné et à l'équipe), fonctions `creer_lien_commande` (fournisseur ou équipe ; `p_renouveler` invalide l'ancien lien), `commande_lien_get` et `demande_deposer` (accessibles sans connexion ; validations strictes, 6 photos maximum de 600 000 caractères, limite de débit 5/heure/téléphone et 40/heure/fournisseur) et `demande_traiter` (traitée ou rejetée avec motif). `vendeur_deposer_commande` accepte désormais `adresse.lat` / `adresse.lng` (la position du client géolocalise l'adresse). Tests : `tests/test_commande_client.sql`, `tests/banc/e2e_commande_client*.js`.

### Zones du Grand Abidjan et position du fournisseur
Migration `20261022000000_zones_grand_abidjan.sql` : `app.zones_defaut(org)` (22 zones, `on conflict do nothing`, jamais appelable par un utilisateur), appliquée aux sociétés existantes et à `amorcer_organisation` ; `maj_adresse_collecte` valide la position GPS et la conserve quand l'adresse est modifiée sans position. Tests : `tests/test_zones_gps.sql`, `tests/banc/e2e_zones_gps*.js`.

### Livreurs externes (commission d'ANGEL'S)
Migration `20261023000000_livreurs_externes.sql` : `livreurs.type` (`interne`/`externe`) et `commission_pct`, `livraisons.part_livreur` et `commission_angels` (figées par un déclencheur quand la course passe à `livree`), `app.retenu_livreur` / `app.solde_livreur` (la part retenue est limitée à l'argent réellement détenu sur la course), `solde_livreurs()` (+ colonne `retenu`) ; `reversement`, `declarer_versement` et `traiter_versement` utilisent le solde net. La fonction `creer-utilisateur` transmet `type` et `commission_pct`. Tests : `tests/test_livreurs_externes.sql`, `tests/banc/e2e_livreurs_externes*.js`.

### Caisse
Migration `20261024000000_caisse.sql` : tables `caisses`, `caisse_sessions` (une seule session ouverte par caisse), `caisse_mouvements` (numéro unique, statuts `en_attente`/`valide`/`rejete`) en lecture seule pour `admin`, `direction`, `caissier` ; **aucune écriture directe**, uniquement `caisse_creer`, `caisse_ouvrir`, `caisse_mouvement`, `caisse_valider`, `caisse_cloturer`, `caisse_regulariser`. Déclencheurs `app.trg_caisse_*` sur `fonds` (reversement en espèces), `reglements_vendeurs` (espèces) et `paiements_livreurs` : écriture automatique validée dans la caisse principale ouverte (ignorée si aucune caisse n'est ouverte). Tests : `tests/test_caisse.sql`, `tests/banc/e2e_caisse*.js`.

### Alertes SOS des livreurs
Migration `20261025000000_sos_livreurs.sql` : table `alertes_sos` (lecture seule ; une seule alerte `ouverte`/`prise` par livreur ; visible de l'administrateur, du superviseur, de la direction et du livreur concerné), fonctions `sos_declencher` (livreur ; 5 par heure ; dernière position connue si le GPS manque) et `sos_traiter` (`prendre` : une seule personne ; `cloturer` et `fausse` avec précision ; le livreur peut seulement signaler une fausse alerte sur la sienne). Tests : `tests/test_sos.sql`, `tests/banc/e2e_sos*.js`.
