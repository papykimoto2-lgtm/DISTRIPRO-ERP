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

## Écart entre l'application et le schéma (à combler avant le branchement)
L'application a reçu après le schéma : les **tournées** (`tournee_id`, `ordre` sur les livraisons), l'**entretien des motos** (table `entretiens`), les **documents numérotés** (table `documents` + compteurs, émission par RPC, jamais modifiables), les **colis étiquetés** (table `colis` : commande, n°, jeton ; scans de prise en charge et de remise) , les **notifications clients** (couvertes par la migration `…_notifications.sql`), la **signature** de livraison (colonne dans `livraisons`, ou fichier dans Supabase Storage) et les paramètres de société (`organisations.config`). Ces éléments sont à ajouter dans une seconde migration, avec les mêmes principes (RLS, RPC, ajout seul pour les documents).

## Étape suivante : brancher l'application HTML
`angels_group_erp.html` utilise encore le stockage du navigateur. Il faut remplacer sa couche de données par `supabase-js` (lecture via tables, écriture via les RPC ci-dessus, connexion par identifiant + mot de passe/PIN) pour que bureau, livreurs et vendeurs partagent les mêmes données.
