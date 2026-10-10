# ANGEL'S GROUP ERP — V1 Livraisons à moto

Fichier unique : `angels_group_erp.html` (aucune dépendance, ouvrable par double-clic ; la carte OpenStreetMap demande Internet).
Il est indépendant de `index.html` (AFRI-BAR).

## Démonstration
PIN : admin `1234` · direction `0000` · superviseur `1111` · caissier `2222` · commercial `3333` · préparateur `4444` · livreurs `0001` (Issa) / `0002` (Kouamé) / `0003` (Sékou).
La session est propre à chaque onglet : ouvrez deux onglets (superviseur + livreur) ; ils se synchronisent via le stockage local.

## Couverture du cahier des charges (V1)
| Module | État |
|---|---|
| Clients, adresses multiples, historique | ✅ (l'adresse est copiée dans la commande : corriger une fiche ne réécrit pas l'historique) |
| Commandes, 12 statuts, transitions contrôlées, horodatage + auteur | ✅ |
| Centre de livraison : affectation, réaffectation motivée, alertes, filtres | ✅ |
| Zones et tarifs paramétrables | ✅ (tournées multi-livraisons : V2) |
| Application livreur mobile : accepter/refuser, prise en charge, départ, itinéraire, appel | ✅ |
| Preuve de livraison par code à usage unique (photo/signature non systématiques) | ✅ code ; signature/photo : à venir |
| GPS avec fraîcheur (récente / ancienne / obsolète), consentement, conservation limitée | ✅ (suivi uniquement pendant une course active) |
| Échecs (motifs paramétrables), nouvelle tentative, retours avec réception et décision de stock | ✅ |
| Paiement à la livraison, écart attendu/déclaré à valider, reversement validé par caissier | ✅ |
| Commissions (fixe / % / mixte), avances, dépenses de mission | ✅ |
| Rentabilité par livreur et par zone | ✅ (par moto : V2) |
| Stock : sortie à la préparation, retour, ajustement tracé | ✅ |
| Carte de l'adresse pour le livreur (destination + sa position) et portail client de géopositionnement | ✅ (voir ci-dessous) |
| Vendeurs partenaires : dépôt de commandes (formulaire ou import CSV), suivi, règlements | ✅ (voir ci-dessous) |
| Rôles, désactivation immédiate d'un compte, journal d'audit | ✅ |
| Incidents et réclamations | ✅ |

## Limites assumées (à traiter avant production)
- **Données stockées dans le navigateur d'un seul appareil.** Pour que le bureau et les téléphones des livreurs partagent les données, il faut un backend (Supabase/PostgreSQL, cahier des charges §17) avec authentification et règles d'accès **côté serveur**. Ici les droits ne sont appliqués que dans l'interface : ce n'est pas une sécurité.
- Les PIN sont hachés de façon simple (démonstration) ; le journal d'audit n'est pas inviolable.
- GPS en arrière-plan écran éteint non garanti en page web : à valider sur les téléphones réels, sinon application native.
- Notifications SMS/WhatsApp : seul un lien WhatsApp pré-rempli pour le code client est fourni.
- Facturation normalisée/fiscale, tournées optimisées, suggestions automatiques d'affectation, gestion des motos (rentabilité, entretien détaillé) : V2/V3.

## Carte livreur et portail client
- **Livreur :** sur chaque mission, « 🗺 Voir sur la carte » affiche la destination et sa propre position (Leaflet + OpenStreetMap, connexion Internet nécessaire). Si l'adresse n'a pas de position, un avertissement s'affiche et le livreur peut demander la position au client en un clic.
- **Client :** le personnel (ou le livreur) génère un lien personnel (« 🔗 Lien portail client », envoi WhatsApp). Le client ouvre la page, place le repère 📍 sur la carte ou utilise sa position actuelle, ajoute une précision (« portail bleu… ») puis confirme.
- **Retour de la position :** si le portail et le logiciel partagent le même stockage (démo, même navigateur), la position est enregistrée directement. Sinon le client l'envoie par WhatsApp et le personnel utilise « 📋 Coller une position reçue » (accepte aussi un lien Google Maps / OpenStreetMap ou « lat, lng »).
- La position s'applique à l'adresse du client et aux commandes non terminées qui l'utilisent ; l'origine (« confirmée par le client » / « saisie par le personnel ») est affichée et tracée dans le journal.
- **Pour que le client puisse ouvrir le lien**, l'application doit être hébergée sur une adresse web (Netlify, Vercel…). Avec un fichier local le lien ne marche que sur le même appareil. La mise à jour automatique sans copier-coller demande le backend partagé.

## Vendeurs en ligne / fournisseurs
- **Compte vendeur partenaire** (créé dans « Vendeurs partenaires », PIN de démo `5555`) : le vendeur ne voit que ses commandes et ses règlements.
- **Dépôt de commande :** formulaire (client, adresse, articles libres avec prix, mode de paiement) ou **import CSV** (`ref;client;tel;zone;quartier;repere;article;qte;prix`, modèle téléchargeable, tout-ou-rien avec messages d'erreur par ligne). Les lignes de même `ref` forment une seule commande.
- **Circuit :** la commande arrive « En attente de confirmation » (alerte au superviseur) → confirmation → réception de la marchandise et préparation (sans mouvement de stock : les articles appartiennent au vendeur) → affectation et livraison comme les autres. La livraison est facturée au client selon la zone.
- **Deux modes de paiement :** le client paie tout au livreur ; ou les articles sont déjà payés au vendeur et le client ne règle que la livraison.
- **Règlement du vendeur :** pour chaque commande livrée et entièrement payée, net = articles − commission (% fixé par vendeur) ; les frais de livraison restent à ANGEL'S GROUP. Le caissier enregistre les règlements (Finance → Vendeurs) ; le vendeur voit son solde. Vérifiez le reversement du livreur avant de régler.
- Le vendeur ne voit ni le code de confirmation, ni les notes internes, ni les livreurs ; il peut annuler tant que la commande n'est pas préparée, et envoyer à son client le lien du portail de position.
- **Limite :** comme le reste, l'isolation entre vendeurs n'est appliquée que dans l'interface tant qu'il n'y a pas de backend. Pour de vrais vendeurs externes sur Internet, le backend (Supabase + règles d'accès) est indispensable ; l'inscription en libre-service reste à construire.
