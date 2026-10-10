# Envoi automatique des messages clients (WhatsApp / SMS)

## Comment ça marche
```
changement de statut d'une commande (confirmée, départ livreur, livrée, échec)
   └─► trigger SQL : prépare le message (modèle de la société + variables) → table notifications [a_envoyer]
          └─► pg_cron (chaque minute) appelle l'Edge Function « envoyer-notifications »
                 ├─ réserve un lot (SKIP LOCKED : jamais deux fois le même message)
                 ├─ envoie chez le prestataire (Twilio ou WhatsApp Cloud API de Meta)
                 └─ enregistre : envoyé / à retenter (3 essais, attente 2 puis 4 min) / échec
          └─► le prestataire rappelle « messagerie-webhook » : livré → lu → échec (statut qui ne fait qu'avancer)
```
Aucune clé du prestataire n'existe dans le navigateur ni dans la base : elles sont dans les **secrets** de l'Edge Function.

## À prévoir avant d'activer
| Sujet | Ce qu'il faut savoir |
|---|---|
| **Compte prestataire** | **Twilio** (WhatsApp + SMS, le plus simple pour démarrer) ou **WhatsApp Business Cloud API de Meta** (WhatsApp seulement). À créer par ANGEL'S GROUP : numéro, vérification de l'entreprise. |
| **Modèles WhatsApp** | Un message envoyé **à l'initiative de l'entreprise** doit utiliser un **modèle pré-approuvé** par WhatsApp (catégorie « utilitaire »). Le texte libre n'est accepté que dans les 24 h après un message du client. Il faut donc faire approuver 4 modèles (confirmation, départ, livraison, échec) et les déclarer dans la configuration ci-dessous. Sans modèle, l'envoi échoue (erreur WhatsApp 131047) : c'est classé « échec définitif ». |
| **Coût** | Facturation à la conversation/au message par le prestataire. À estimer selon le nombre de livraisons par jour. |
| **Consentement** | WhatsApp exige l'accord du client pour recevoir des messages. La colonne `clients.consent_notifications` (vrai par défaut) permet de désactiver l'envoi pour un client qui refuse. À recueillir à la prise de commande. |
| **SMS** | Twilio envoie des SMS. Pour un agrégateur local (Orange, MTN, …), il faudra ajouter un adaptateur dans `functions/_shared/messagerie.ts` (une fonction de ~20 lignes). |
| **Données personnelles** | Le message de départ contient le **code de confirmation** : il part chez le prestataire. À mentionner dans votre politique de confidentialité. |

## Mise en service
1. Appliquer les migrations `20261010000000_angels_erp_schema.sql` puis `20261011000000_notifications.sql`.
2. Déployer les fonctions :
   ```bash
   supabase functions deploy envoyer-notifications
   supabase functions deploy messagerie-webhook --no-verify-jwt   # le prestataire n'a pas de compte : la signature fait foi
   ```
3. Définir les secrets (jamais dans le code) :
   ```bash
   supabase secrets set CRON_SECRET=<longue-valeur-aleatoire> \
     WEBHOOK_URL=https://<ref>.supabase.co/functions/v1/messagerie-webhook
   # Twilio
   supabase secrets set TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_WHATSAPP_FROM=+1415... TWILIO_SMS_FROM=+...
   # ou Meta WhatsApp Cloud
   supabase secrets set META_WA_TOKEN=... META_WA_PHONE_ID=... META_APP_SECRET=... META_VERIFY_TOKEN=<valeur-de-votre-choix>
   ```
4. Chez le prestataire, déclarer l'URL de rappel : `WEBHOOK_URL` (Twilio ajoute lui-même les paramètres ; Meta : abonnement « messages » avec `META_VERIFY_TOKEN`).
5. Configurer la société (SQL Editor) — exemple Twilio avec modèles :
   ```sql
   update public.organisations set config = config || jsonb_build_object('messagerie', jsonb_build_object(
     'auto', true, 'provider', 'twilio', 'canal', 'whatsapp', 'indicatif', '225',
     'templates', jsonb_build_object(
       'confirmee', jsonb_build_object('content_sid','HX...', 'vars', jsonb_build_array('client','numero','solde')),
       'en_cours',  jsonb_build_object('content_sid','HX...', 'vars', jsonb_build_array('client','livreur','numero','heure','code')),
       'livree',    jsonb_build_object('content_sid','HX...', 'vars', jsonb_build_array('client','numero')),
       'echouee',   jsonb_build_object('content_sid','HX...', 'vars', jsonb_build_array('client','numero','motif'))))) ;
   ```
   (Meta : `'provider','meta'` et, pour chaque événement, `{ "name": "nom_du_modele", "lang": "fr", "vars": [...] }`.)
   L'ordre de `vars` doit être celui des variables {{1}}, {{2}}… du modèle approuvé.
6. Planifier l'envoi chaque minute (extensions `pg_cron` et `pg_net` activées) :
   ```sql
   select cron.schedule('envoyer-notifications', '* * * * *', $$
     select net.http_post(
       url := 'https://<ref>.supabase.co/functions/v1/envoyer-notifications',
       headers := jsonb_build_object('x-cron-secret', '<CRON_SECRET>', 'Content-Type', 'application/json')) $$);
   ```
7. **Tester avec le bac à sable Twilio** (numéro de test WhatsApp) avant de passer en production.

## Suivi et incidents
- Les statuts d'un message : `a_envoyer` → `envoi_en_cours` → `envoye` → `livre` → `lu`, ou `echec` / `ignore`.
- Un message en `echec` (numéro invalide, modèle refusé, 3 erreurs réseau…) peut être corrigé puis **relancé** par le superviseur (`notification_renvoyer`) ; il peut aussi être modifié tant qu'il est en attente, ou ignoré.
- **Garantie d'envoi « au moins une fois »** : si l'Edge Function s'arrête **après** avoir envoyé mais **avant** d'enregistrer le résultat, le message reste « en cours d'envoi » et n'est **pas renvoyé automatiquement** (pour ne pas écrire deux fois au client). Surveillez les messages bloqués : `select * from notifications where statut='envoi_en_cours' and maj_at < now() - interval '10 minutes';`
- Pour revenir en mode manuel : `'auto': false` — les messages restent en file et s'envoient depuis l'écran « Notifications » de l'application.

## Tests
- `supabase/tests/messagerie.test.mjs` (14 vérifications, sans réseau) : numéros, requêtes Twilio/Meta, classement des erreurs, signatures des accusés.
  `node --experimental-strip-types supabase/tests/messagerie.test.mjs`
- `supabase/tests/test_notifications.sql` (43 vérifications sur PostgreSQL) : création des messages à chaque étape, anti-doublon, réservation sans double envoi, reprises, accusés, droits d'accès, consentement.
- **Non testé ici :** les vrais appels à Twilio / Meta (pas de compte) et le déploiement sur un projet Supabase. Ils doivent être validés avec le bac à sable du prestataire.
