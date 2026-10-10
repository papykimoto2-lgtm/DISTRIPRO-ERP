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
| Zones et tarifs paramétrables | ✅ |
| Tournées multi-livraisons : regroupement, ordre de passage proposé et ajustable, estimation distance/durée, suivi d'avancement | ✅ |
| Application livreur mobile : accepter/refuser, prise en charge, départ, itinéraire, appel | ✅ |
| Preuve de livraison par code à usage unique (photo/signature non systématiques) | ✅ code + signature ; photo : à venir (demande un stockage de fichiers côté serveur) |
| GPS avec fraîcheur (récente / ancienne / obsolète), consentement, conservation limitée | ✅ (suivi uniquement pendant une course active) |
| Échecs (motifs paramétrables), nouvelle tentative, retours avec réception et décision de stock | ✅ |
| Paiement à la livraison, écart attendu/déclaré à valider, reversement validé par caissier | ✅ |
| Commissions (fixe / % / mixte), avances, dépenses de mission | ✅ |
| Rentabilité par livreur, par zone et par moto | ✅ |
| Motos : entretien et réparations (type, coût, km), prochain entretien, immobilisation, historique | ✅ |
| Tableau de bord filtrable par période, zone, livreur et type de commande | ✅ |
| Stock : sortie à la préparation, retour, ajustement tracé | ✅ |
| Carte de l'adresse pour le livreur (destination + sa position) et portail client de géopositionnement | ✅ (voir ci-dessous) |
| Vendeurs partenaires : dépôt de commandes (formulaire ou import CSV), suivi, règlements | ✅ (voir ci-dessous) |
| Documents numérotés : facture, reçu de paiement, avoir, bon de livraison (preuve de livraison distincte de la facture) | ✅ (voir ci-dessous) |
| Notifications clients : messages automatiques par étape, modèles modifiables, journal d'envoi | ✅ envoi WhatsApp manuel en un clic |
| Signature électronique du destinataire (obligatoire au-delà d'un seuil de valeur) | ✅ |
| Étiquettes colis à QR code, scan à la prise en charge et à la remise, recherche par scan | ✅ (voir ci-dessous) |
| Rôles, désactivation immédiate d'un compte, journal d'audit | ✅ |
| Incidents et réclamations | ✅ |

## Limites assumées (à traiter avant production)
- **Données stockées dans le navigateur d'un seul appareil.** Pour que le bureau et les téléphones des livreurs partagent les données, il faut un backend (Supabase/PostgreSQL, cahier des charges §17) avec authentification et règles d'accès **côté serveur**. Ici les droits ne sont appliqués que dans l'interface : ce n'est pas une sécurité.
- Les PIN sont hachés de façon simple (démonstration) ; le journal d'audit n'est pas inviolable.
- GPS en arrière-plan écran éteint non garanti en page web : à valider sur les téléphones réels, sinon application native.
- Notifications SMS/WhatsApp : les messages sont préparés automatiquement mais envoyés à la main (lien WhatsApp pré-rempli) ; l'envoi automatique (WhatsApp / SMS via Twilio ou WhatsApp Cloud) est préparé côté serveur dans `supabase/` (guide : `supabase/MESSAGERIE.md`) et s'active avec le backend.
- Facturation normalisée/fiscale, optimisation de tournées avec trafic réel, suggestions automatiques d'affectation, notifications clients automatiques : V2/V3.

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

## Tournées et motos
- **Tournée :** dans « Centre de livraison », « 🔁 Créer une tournée » regroupe au moins 2 commandes prêtes sur un livreur. L'ordre de passage est proposé (plus proche voisin depuis sa dernière position, adresses sans GPS en dernier) et reste ajustable avec ↑ ↓ tant que l'arrêt n'a pas démarré. Le livreur voit « Tournée T-0001 · arrêt 2/4 » et ses missions dans cet ordre ; il garde la liberté d'adapter son trajet.
- **Estimation :** distance à vol d'oiseau × 1,35, 18 km/h en moyenne, 8 min par arrêt. C'est une indication, pas un itinéraire routier ; elle ignore le trafic (un vrai calcul d'itinéraire demande un service cartographique externe).
- **Entretien :** bouton « 🔧 Entretien » par moto (vidange, pneus, freinage, réparation, pièces…) avec date, kilométrage, coût, prochain entretien, et statut de la moto après intervention. Une moto en panne ou immobilisée reste bloquée pour les missions.
- **Rentabilité par moto :** frais de livraison − commissions − dépenses de mission − entretien. Les coûts d'entretien sont cumulés depuis le début, comme les livraisons ; ce n'est pas un bénéfice comptable.

## Documents, notifications, signature
- **Documents :** depuis une commande — « Établir la facture », « Reçu de paiement », « ↩ Avoir », « 🖨 Bon de livraison ». Chaque document reçoit un numéro de séquence continue par année et par type (`FAC-2026-0001`, `REC-`, `AVO-`, `BL-`) et reste figé : il ne se modifie ni ne se supprime, une erreur se corrige par un avoir (limité au montant de la facture). Le menu « Documents » les liste et permet de les rouvrir ; impression ou PDF via le navigateur. Pour une commande de vendeur partenaire, la facture ne porte que les frais de livraison, établie au nom du vendeur ; les articles restent facturés par lui.
- **Bon de livraison :** il atteste de la remise (livreur, date, destinataire, code validé, position GPS, signature) et précise qu'il ne tient pas lieu de facture.
- **Avertissement :** ce sont des documents de gestion. Si l'entreprise est assujettie à la facturation normalisée électronique, la facture réglementaire doit être émise par le dispositif officiel ; la mention en pied de page, l'adresse, le NIF et le RCCM se règlent dans Paramètres.
- **Notifications :** à la confirmation, au départ du livreur (avec l'heure estimée et le code à donner), à la livraison et en cas d'échec, un message est préparé et placé dans le menu « Notifications ». Le superviseur l'envoie par WhatsApp en un clic, le modifie ou l'ignore. « Envoyé » signifie que la conversation WhatsApp a été ouverte, pas que le client l'a reçue. Les modèles et les événements actifs se règlent dans Paramètres.
- **Signature :** dans l'écran de confirmation du livreur, un cadre de signature au doigt est obligatoire dès un montant de commande réglable (100 000 F par défaut, 0 = jamais), facultatif en dessous. Elle apparaît sur le bon de livraison.

## Étiquettes colis et QR codes
- **Impression :** sur une commande confirmée, « 🏷 Étiquettes colis » demande le nombre de colis et génère une étiquette 100 × 150 mm par colis : numéro de commande, **QR code unique**, « 1/3 », zone de livraison en grand, quartier et repère, client, code court de 5 caractères sous le QR, expéditeur pour les vendeurs partenaires, mention URGENT. Le montant à encaisser et le téléphone du client ne s'impriment que si vous les activez dans Paramètres (le montant affiché dans l'application fait foi).
- **Réimpression :** les mêmes QR codes sont conservés. Changer le nombre de colis invalide les étiquettes déjà collées (et c'est refusé dès qu'un colis a été scanné).
- **Prise en charge :** quand la commande a des étiquettes, le livreur doit scanner chaque colis (caméra) avant de partir. Un colis d'une autre commande est refusé avec le numéro de la commande concernée ; une étiquette inventée ou périmée est refusée.
- **Remise au client :** la confirmation de livraison exige de scanner de nouveau tous les colis remis.
- **Secours :** si la caméra est refusée, absente ou si l'étiquette est abîmée, le livreur saisit le code de 5 caractères imprimé sous le QR ; l'application enregistre « saisi » plutôt que « scanné ».
- **Personnel :** « 📷 Scanner une étiquette » (liste des commandes) ouvre la commande correspondante.
- **Lecture :** BarcodeDetector du navigateur s'il existe, sinon jsQR (intégré au fichier, hors ligne). La caméra exige une page en **https** (ou localhost) ; depuis un simple fichier local ou une adresse http, elle peut être refusée : la saisie du code reste possible.
- **Réglages :** le scan obligatoire se désactive dans Paramètres. Une alerte signale les commandes prêtes sans étiquettes.
- **Composants intégrés :** qrcode-generator 1.4.4 (MIT) et jsQR 1.4.0 (Apache-2.0).
