# ANGEL'S GROUP ERP — V1 Livraisons à moto

Fichier unique : `index.html` (aucune dépendance, ouvrable par double-clic ; la carte OpenStreetMap demande Internet).

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
- **Paiement du client final — chez le fournisseur et/ou chez le livreur désigné par ANGEL'S GROUP** (champ *Paiement du client* du formulaire, de la saisie WhatsApp et colonne facultative `paye_chez_moi` du CSV) :
  - *Tout chez le livreur* : il encaisse articles + livraison.
  - *Partagé* : le vendeur indique la part des articles déjà payée chez lui (acompte, avance) ; le livreur n'encaisse que le reste (articles restants + livraison).
  - *Articles payés chez moi* : le livreur n'encaisse que la livraison.
  La saisie WhatsApp reconnaît « avance 10000 », « acompte… », « déjà payé ». La livraison est toujours encaissée par le livreur. **Règlement du vendeur** : ANGEL'S GROUP ne lui reverse que la part qu'ELLE a encaissée, moins la commission ; la part payée directement chez le fournisseur n'entre ni dans la caisse du livreur ni dans le règlement (pas de commission dessus). Le montant payé chez le fournisseur est déclaré par le vendeur ; il figure sur la commande, sur l'écran du livreur (« dont X déjà payés chez le fournisseur ») et sur la page de suivi du client (montant à régler).
- **Règlement du vendeur :** pour chaque commande livrée et entièrement payée, net = articles − commission (% fixé par vendeur) ; les frais de livraison restent à ANGEL'S GROUP. Le caissier enregistre les règlements (Finance → Vendeurs) ; le vendeur voit son solde. Vérifiez le reversement du livreur avant de régler.
- Le vendeur ne voit ni le code de confirmation, ni les notes internes, ni les livreurs ; il peut annuler tant que la commande n'est pas préparée, et envoyer à son client le lien du portail de position.
- **Limite :** comme le reste, l'isolation entre vendeurs n'est appliquée que dans l'interface tant qu'il n'y a pas de backend. Pour de vrais vendeurs externes sur Internet, le backend (Supabase + règles d'accès) est indispensable ; l'inscription en libre-service reste à construire.

## Photos des commandes (fournisseur)
Le fournisseur joint des photos ou captures d'écran à ses commandes (jusqu'à **8 par commande**, réduites automatiquement) :
- **à la création** : bloc « Photos / captures des articles » dans *Nouvelle commande* (et déjà via la saisie WhatsApp et les demandes de clients) ;
- **après coup** : bouton **📷** sur la ligne de la commande ou « Ajouter des photos » dans son détail, tant que la commande n'est pas livrée, annulée ou retournée. Le fournisseur peut aussi **retirer** une photo. L'équipe ANGEL'S GROUP (administrateur, superviseur, commercial) peut ajouter et retirer ; le livreur et l'équipe consultent. Une commande terminée est en lecture seule, un fournisseur ne touche jamais aux commandes d'un autre.

## Zones du Grand Abidjan et de la périphérie, position du fournisseur
- **22 zones de livraison par défaut** (tarif et délai modifiables dans *Paramètres*) : les dix communes d'Abidjan (Plateau, Cocody, Marcory, Treichville, Adjamé, Koumassi, Attécoubé, Abobo, Yopougon, Port-Bouët), Bingerville, Anyama, Songon, Grand-Bassam, Dabou, Bonoua, Azaguié, Alépé, Sikensi, Jacqueville, Assinie et « Autre localité (tarif à convenir) ». Les installations existantes reçoivent les zones manquantes une seule fois, sans toucher à vos tarifs ni ressusciter une zone supprimée.
- **Quartiers suggérés par zone** (environ 200) dans tous les formulaires d'adresse, y compris la page de commande des clients ; la saisie libre reste possible. L'analyse des messages WhatsApp reconnaît aussi ces zones et quartiers.
- **Position GPS du fournisseur** : dans « Mon adresse de collecte », bouton « 📍 Utiliser ma position actuelle » (à toucher depuis la boutique) ou collage d'un lien Google Maps / « latitude, longitude ». Le livreur de collecte a alors l'itinéraire exact ; modifier l'adresse sans position conserve la position déjà enregistrée.

## Le client commande lui-même chez son fournisseur
Chaque fournisseur dispose d'un **lien et d'un QR code de commande** (bouton « 🔗 Lien de commande client » dans *Mes commandes*), à partager sur WhatsApp, en statut ou en boutique. Sans compte ni mot de passe, le client y :
- ajoute ses **articles** : désignation, quantité, **prix unitaire s'il le connaît**, et la **capture d'écran / photo** du produit (jusqu'à 6) ;
- indique son nom, son téléphone, sa zone, son quartier, un repère, et envoie sa **position GPS** d'un tap ;
- reçoit une **référence** de demande et un bouton pour joindre ANGEL'S GROUP sur WhatsApp.

La demande arrive dans **« 📥 Demandes reçues de vos clients »**. Elle n'est **pas** une commande : le prix donné par le client n'est qu'une proposition. Le fournisseur la vérifie dans l'écran de saisie habituel (préremplie, captures et position jointes), fixe les prix manquants puis **crée la commande** (ANGEL'S GROUP confirme et collecte comme d'habitude) ou **refuse** avec un motif. La position du client devient la position GPS de l'adresse de livraison : le livreur aura la carte. **Sans serveur (version actuelle en ligne)** : le lien contient lui-même le nom du fournisseur et ses zones, donc il s'ouvre sur n'importe quel téléphone. Le client remplit sa commande puis touche « Envoyer ma commande sur WhatsApp » : un message structuré part au numéro de la fiche vendeur (position GPS en lien carte), et le client ajoute la capture de chaque article sur la page et, sur téléphone, le bouton « Envoyer message + captures » les partage avec le texte vers WhatsApp (il choisit la conversation du fournisseur ; sans partage de fichiers, il joint les captures à la main). Le fournisseur colle ce message dans « Saisie depuis WhatsApp » : client, articles, quantités, prix et position GPS sont préremplis. **Avec le cloud**, la commande, ses captures et sa position arrivent directement dans « Demandes reçues », sans passer par WhatsApp. *Renouveler* le lien (cloud) invalide l'ancien. Protection : jeton secret de 256 bits, 5 demandes par heure et par téléphone et 40 par fournisseur, photos limitées en taille, aucune lecture possible par le public.

## Bouton SOS et confort d'affichage du livreur
- **🆘 SOS** : un bouton rouge reste visible dans l'application du livreur, y compris par-dessus une offre de course. Le livreur choisit la situation (accident, agression ou vol, moto en panne, malaise ou blessure, autre), ajoute une précision, puis **maintient le bouton 1,5 s** (un appui accidentel n'envoie rien). L'alerte part avec sa position ; il voit aussitôt les boutons **Appeler le superviseur**, **WhatsApp** et les **numéros d'urgence**, et peut annuler s'il s'agit d'une fausse alerte. Une seule alerte active par livreur, 5 par heure au maximum.
- **Côté équipe** : l'administrateur, les superviseurs et la direction voient une **barre rouge persistante** (livreur, situation, précision, heure) avec **appeler** et **position sur la carte**, une **sirène** et une notification système à chaque nouvelle alerte. L'administrateur ou le superviseur **prend en charge** (une seule personne), puis **clôture** en écrivant ce qui a été fait, ou classe en **fausse alerte**. Le livreur voit l'avancement (« prise en charge par … ») en direct. Rien ne se supprime.
- **Réglages** : *Paramètres → Livreurs & GPS → Alertes SOS* : téléphone d'astreinte et numéros d'urgence affichés (110, 185, 180 proposés : **à vérifier**).
- **⚙ Préférences** (en haut de l'écran livreur, mémorisées sur le téléphone) : **gros caractères et gros boutons** ; **économie de données** (vignettes masquées, photos envoyées jusqu'à 3 fois plus légères, vérification des nouvelles courses deux fois moins fréquente, carte seulement après confirmation).
- Limite : comme pour les courses, la sirène fonctionne tant que l'application est ouverte ; application fermée, il faudra la notification push serveur.

## Course proposée au livreur et itinéraire optimisé (à la Yango)
- **Le téléphone sonne** quand une commande est affectée : sonnerie, vibration, notification système (si autorisée) et **fiche plein écran** avec le **gain du livreur** (frais de livraison, commission d'ANGEL'S déduite pour un externe), la **zone**, la **distance et la durée depuis sa position**, le **montant à encaisser**, la mention URGENT et, s'il a déjà des courses, le **détour** que celle-ci ajoute à son itinéraire. Compte à rebours de 60 s (la sonnerie s'arrête, la course reste dans sa liste).
- **Accepter ou décliner** : un refus demande un **motif** (trop loin, moto en panne ou plus de carburant, déjà trop chargé, pause, zone inconnue, autre à préciser) ; le superviseur est informé et la commande redevient disponible.
- **Plusieurs courses à la fois** : le livreur peut en accepter autant qu'il veut. La carte **🧭 Itinéraire conseillé** calcule l'**ordre de passage le plus court** (exact jusqu'à 9 arrêts, heuristique au-delà) depuis sa position, avec distance de chaque tronçon, durée totale (18 km/h et 8 min par arrêt), heure de fin et gain par rapport à l'ordre d'arrivée des commandes. Les missions s'affichent dans cet ordre (« Arrêt n°2 sur 4 ») et **« Ouvrir dans Maps »** lance le trajet multi-arrêts en mode moto. Les adresses sans GPS passent en fin de parcours, groupées par zone.
- **Détection** : en ligne, le logiciel vérifie toutes les 6 s s'il y a une nouvelle offre (requête légère). Le bouton **« Activer la sonnerie »** (une seule fois par téléphone) débloque le son et les notifications.
- **Limite importante** : la sonnerie fonctionne tant que l'application est ouverte, même en arrière-plan. **Application fermée ou téléphone verrouillé, il faut une notification push serveur** (Web Push : clés VAPID + fonction serveur après création du projet Supabase). Le service worker est déjà prêt à les recevoir. Distances et durées sont des estimations à vol d'oiseau × 1,35, sans trafic.

## Paramètres rangés par onglets
La page **Paramètres** n'est plus une longue page à faire défiler : elle est découpée en onglets — **🗺️ Zones & tarifs**, **🏍️ Livreurs & GPS** (rémunération par défaut, GPS, dossiers des livreurs, étiquettes colis), **📝 Listes** (motifs d'échec, catégories d'incident), **🏢 Société & documents**, **💳 Paiements** (comptes Mobile Money), **💬 Notifications** et **💾 Données** (mode démonstration). Un seul bouton **💾 Enregistrer les paramètres**, toujours visible en haut, enregistre les réglages de tous les onglets ; changer d'onglet ne fait rien perdre et l'onglet actif reste affiché après l'enregistrement.

## Photos CNI et permis dès la fiche livreur
Le formulaire **Nouveau livreur** (et **Modifier**) comporte quatre emplacements photo : **portrait**, **CNI / pièce d'identité recto**, **verso** et **permis de conduire**. Chaque emplacement ouvre l'appareil photo ou la galerie, réduit l'image automatiquement, permet de la remplacer ou de la retirer, et les images existantes sont rechargées à la modification. Les photos sont les mêmes que dans **📁 Dossier** (numéros, dates d'expiration, contacts et accord restent à y compléter) ; elles ne sont visibles que de l'administrateur, du superviseur et du livreur concerné. Le portrait sert de vignette dans la liste.

## Menu rangé selon la marche en avant
La barre latérale suit le déroulement d'une livraison, avec des titres de section : **Pilotage** (tableau de bord, carte) → **Tiers & partenaires** (vendeurs, clients) → **Commandes** (commandes, notifications) → **Stock & préparation** (produits, journal des mouvements, inventaire) → **Livraison** (centre de livraison, livreurs et motos, incidents) → **Argent** (finance, caisse) → **Contrôle & documents** (états périodiques, documents, audit) → **Administration** (utilisateurs, paramètres). Chaque profil ne voit que ses sections et s'ouvre sur sa première page utile (le caissier sur *Finance*, le vendeur sur *Mes commandes*). **Sur tablette et smartphone** (écran de 1 024 px ou moins), le menu devient un **menu déroulant vertical** : une barre fixe en haut avec le bouton ☰, le titre de la page en cours et l'heure ; le bouton ouvre la liste verticale (avec les titres de section, l'heure, la couleur du logiciel et la déconnexion), qui se ferme en choisissant une page, en touchant en dehors, avec ✕ ou avec Échap. Le rafraîchissement automatique ne ferme pas un menu ouvert.

## Caisse (espèces)
Menu **💵 Caisse** (administrateur, direction, caissier), conçu d'après le module caisse d'ImmoSuite :
- **Caisses** (principale compte 571, petite caisse 572…) créées par l'administrateur. Chaque caisse a des **sessions** : *Ouvrir la caisse* (fond repris du dernier comptage ; seul l'administrateur peut le modifier, avec un motif) puis *Clôturer* (comptage réel, **écart affiché en direct**, justification obligatoire si l'écart n'est pas nul).
- **Bons d'entrée (BE) et de sortie (BS)** numérotés `BE-571-AAAAMMJJ-001` : montant, motif, déposant ou bénéficiaire, pièce justificative, catégorie. Un bon saisi par un **caissier** est **en attente** et ne compte pas dans le solde ; l'**administrateur ou la direction** le **valide** (une sortie supérieure au solde est refusée) ou le **rejette** avec motif. Un bon de l'administrateur est validé d'office. **Rien ne se supprime.** Les bons validés s'impriment (visa, signatures).
- **Clôture** refusée tant qu'un bon est en attente. Un **écart** reste affiché en rouge jusqu'à sa **régularisation** par l'administrateur ou la direction (décision écrite).
- **Flux en espèces automatiques** dans la caisse principale ouverte : reversements des livreurs en espèces (entrée), règlements aux vendeurs en espèces et paiements aux livreurs (sorties). Les paiements Mobile Money n'entrent pas en caisse.
- **Tableau de bord** par jour, mois ou année : solde temps réel, encaissements, décaissements, flux net, bons à valider, écarts non régularisés, écart de clôture, graphique sur 12 mois, top des dépenses, détail par caisse.
- **Brouillard de caisse** par session ou par période, imprimable (fond d'ouverture, totaux, fond compté, écart, signatures « Caissier(ère) » et « Vérifié par ») et exportable en CSV.
Hors périmètre volontairement : ventilation comptable SYSCOHADA, budgets, import CSV et envoi automatique de l'état (présents dans ImmoSuite).

## Livreurs externes : commission d'ANGEL'S GROUP
Dans la fiche d'un livreur, **Type : Externe — partenaire (sa propre moto)** et **Commission d'ANGEL'S sur les frais de livraison (%)** (20 % proposé). Le livreur externe n'a pas de salaire : à chaque course livrée, il **garde ses frais de livraison moins la commission** d'ANGEL'S GROUP, directement sur l'argent qu'il a encaissé. Exemple : frais 1 500 F à 20 % → commission 300 F pour ANGEL'S, 1 200 F pour le livreur ; encaissement 16 000 F → il reverse 14 800 F.
- La commission est **figée à la livraison** : changer le taux ne modifie pas les courses passées.
- *Finance* affiche le restant à reverser net et la part gardée ; le reversement (comptant ou Mobile Money) et la déclaration du livreur sont plafonnés à ce net.
- Si le client a payé **directement sur le compte d'ANGEL'S** (le livreur n'a rien détenu), il ne peut pas retenir sa part : le reste lui est dû et se règle par *Payer un livreur*.
- Les états périodiques et la marge comptent la part du livreur externe comme coût de la course et font apparaître la **commission d'ANGEL'S** comme gain. Un livreur interne ne change pas (fixe par course, % des frais ou mixte).

## Suivi des versements : en validation → encaissé
Chaque versement déclaré par un livreur suit trois états visibles par tous : **⏳ En validation** (déclaré, la caisse vérifie), **✅ Encaissé** (validé par la caisse, avec la date et le nom du valideur ; le reversement est alors enregistré et le solde du livreur diminue) ou **✖ Rejeté** (avec le motif). Le menu **Finance** affiche une **pastille rouge** avec le nombre de versements à valider (sur smartphone, sur le bouton ☰), et l'onglet **📲 Versements** de *Finance* liste toutes les déclarations avec leurs compteurs (en validation, encaissés aujourd'hui et au total, rejetés), un filtre par état, une recherche par livreur ou référence, et les boutons **✔ Encaissé** / **✖ Rejeter** pour le caissier et l'administrateur (la direction consulte). L'écran du livreur montre le même état : « ⏳ En validation » puis « ✅ Encaissé le … ». La pastille du menu **Caisse** compte de la même façon les bons à valider.

## Versements des livreurs : au comptant ou par Mobile Money
Quand le client règle à la réception, le livreur encaisse puis reverse à ANGEL'S GROUP :
- **À la livraison** : le livreur choisit le mode de paiement du client (Espèces, Wave, Orange Money, MTN MoMo, Moov Money…). En Mobile Money, la **référence de la transaction** (identifiant du SMS) est obligatoire et ne peut servir qu'une fois. Case **« payé directement sur le compte d'ANGEL'S GROUP »** : le client a payé sur le compte de la société, le livreur ne détient rien et n'a rien à reverser (l'opération reste tracée avec sa référence).
- **Versement au comptant** : le livreur remet les espèces au caissier, qui les **enregistre** (*Finance → Enregistrer un reversement*).
- **Versement par Mobile Money** : l'écran du livreur (« 💰 Mon argent à reverser ») montre le montant dû et les **comptes Mobile Money d'ANGEL'S GROUP** (à renseigner dans *Paramètres → Paiements et versements*). Il envoie la somme, puis **déclare le versement** (montant, opérateur, référence). Le **caissier vérifie la réception** dans son application Mobile Money puis **valide** (le reversement est alors enregistré avec la référence) ou **rejette** avec motif. Tant que ce n'est pas validé, le montant reste à la charge du livreur ; il ne peut pas déclarer plus que son restant dû.
- Un reversement saisi au guichet en Mobile Money exige aussi la référence. *Finance* distingue espèces / Mobile Money détenu / Mobile Money direct, affiche la référence dans le journal des fonds et exporte les **paiements Mobile Money (CSV)** pour le rapprochement avec le relevé de l'opérateur ; les états périodiques ventilent versements et encaissements par Mobile Money.

## Collecte des colis chez le vendeur
Une fois les commandes d'un vendeur confirmées, ANGEL'S GROUP passe récupérer les colis chez lui :
1. **Superviseur / administrateur** : *Centre de livraison → Collectes chez les vendeurs* liste, par vendeur, les commandes confirmées à collecter. **🚚 Planifier la collecte** : choix des commandes, du livreur, du créneau de passage et de l'adresse de collecte (mémorisée sur la fiche du vendeur). Un tableau suit les collectes (réaffecter, annuler avec motif, imprimer le **bon de collecte**). Alertes sur le tableau de bord : commandes à collecter, collecte non réalisée, créneau dépassé.
2. **Vendeur** : *Mes commandes → Collecte de mes colis* : son adresse de collecte (modifiable), le créneau, le prénom du livreur et un **code à 4 chiffres à remettre au livreur contre les colis** (le livreur ne le voit pas, comme le code de livraison du client).
3. **Livreur** : une carte *Collecte* (vendeur, téléphone, adresse, articles par commande, itinéraire) : **Accepter**, **Je pars**, puis **Colis collectés** : code du vendeur (5 essais) et nombre de colis pris pour chaque commande ; ou **Impossible** avec motif (le superviseur réaffecte).
4. **Préparateur / administrateur** : **📦 Collectes à réceptionner** (page Commandes) : comptage des colis arrivés au dépôt ; les commandes complètes passent automatiquement en **préparation**, celles avec écart restent « confirmées » pour traitement avec le vendeur. **Chaque écart ouvre automatiquement un incident** (page *Incidents & retours*, journalisé) : *Colis manquant* (moins de colis reçus que collectés, ou commande non remise : 0 colis collecté) ou *Écart de colis* (colis en trop). Le formulaire de réception affiche l'écart et l'incident à venir avant validation.
Tant qu'une commande est dans une collecte en cours, le bouton « Marchandise reçue » est remplacé par le suivi de la collecte (une commande déposée directement au dépôt reste possible sans collecte).

## Saisie des commandes depuis WhatsApp (vendeurs partenaires)
Le fournisseur ne retape plus rien : bouton **💬 Saisie depuis WhatsApp** dans *Mes commandes*.
1. **Coller** le message du client (ou une conversation), ou **importer l'export WhatsApp** (*Exporter la discussion* → fichier **.txt** ou **.zip** avec médias), ou **partager directement depuis WhatsApp** vers l'application installée (Android : Partager → ANGEL'S GROUP) ; **captures d'écran** de l'article : ajout, glisser, ou **Ctrl+V**.
2. L'application **remplit les fiches** : nom, numéro WhatsApp (depuis le texte ou le numéro de l'expéditeur), zone et quartier (Angré, Sicogi, Biétry… reconnus), repère, articles avec quantité et prix (« 2 robes wax 15000f », « Riz 25kg x3 14.500 », « 250k », total ou prix unitaire), paiement. Plusieurs clients à la suite (lignes vides ou export de groupe) = plusieurs fiches ; dans une discussion à deux, la conversation est fusionnée (la quantité du client et le prix du vendeur donnent une seule ligne).
3. Le vendeur **vérifie et corrige** chaque fiche (avertissements : téléphone, zone, prix à saisir…), rattache les **captures à la bonne commande**, puis crée toutes les commandes en un clic. Elles arrivent « en attente de confirmation » ; les captures restent **jointes à la commande** (visibles par l'équipe, le préparateur et le livreur de la mission : bouton *📷 Photos*).
Limites : l'analyse repose sur des règles (pas d'intelligence artificielle) — toujours relire ; les captures ne sont pas lues automatiquement (lecture optique non incluse) ; le partage direct depuis WhatsApp fonctionne sur Android avec l'application installée (sur iPhone : copier/coller ou exporter la discussion).

## Journal des mouvements, inventaire, états périodiques
- **📒 Journal des mouvements** : tous les mouvements de stock (entrée, sortie sur commande, annulation, retour, ajustement, inventaire) avec le **stock après chaque mouvement**, la référence et l'auteur ; filtres période / produit / type ; export CSV et impression. Bouton **➕ Entrée de stock** (réception de marchandise : quantité, référence de bon de livraison obligatoire, coût d'achat). Le journal est en ajout seul : une erreur se corrige par un mouvement inverse.
- **📋 Inventaire** : ouverture d'un inventaire (stock théorique relevé), **fiche de comptage imprimable**, saisie des quantités comptées avec observation (comptage à l'aveugle par défaut, case « Afficher le stock théorique »), progression, puis **validation par l'administrateur** (tout doit être compté) : chaque écart devient un mouvement « inventaire » ; les ventes faites pendant le comptage restent valables. Un inventaire validé ne change plus ; historique et rapport imprimable avec la valeur des écarts au coût d'achat ; annulation motivée.
- **🧾 États périodiques** (jour, 7/30 jours, mois, mois dernier, trimestre, année ou dates précises) : état des stocks (ouverture, entrées, sorties, retours, ajustements, inventaire, clôture, valeur au coût et à la vente), activité de livraison, caisse (encaissements, reversements, dépenses, commissions, règlements vendeurs) ; impression / PDF et export CSV.
- Le **coût d'achat** se saisit sur la fiche produit ou à chaque entrée de stock.

## Application installable (PWA)
Le site peut s'installer comme une application sur téléphone, tablette et ordinateur (icône sur l'écran d'accueil, plein écran, ouverture hors connexion de la coque et de la démonstration). Fichiers : `manifest.webmanifest`, `sw.js`, `icons/`. Sur Android et Chrome/Edge : bouton **📲 Installer l'application** (écran d'accueil, menu, écran du livreur) ou menu du navigateur ; sur iPhone : Partager → *Sur l'écran d'accueil*. Il faut un site en https (Vercel). Les données Supabase ne sont jamais mises en cache : sans réseau, seul l'écran s'ouvre. Pour publier une nouvelle version, il suffit de remplacer `index.html` ; pour forcer le renouvellement du cache, changez `V` dans `sw.js`.

## Carte en direct (manager)
Menu **🗺️ Carte en direct** (administrateur, superviseur, direction) : tous les livreurs sur une carte centrale, en couleur selon leur état (libre, en mission, indisponible), avec leurs initiales, la destination de chaque course (📍), un trait vers la destination pour les courses en cours et les commandes à affecter (⏳, lien « Affecter »). La liste à droite donne l'état de chacun et un clic centre la carte sur lui ; filtres par zone et par état, bouton « Tout voir ». Mise à jour automatique (toutes les 15 s en mode connecté). Un livreur sans position partagée figure dans la liste mais pas sur la carte ; une position ancienne est affichée en pointillés orange. En démonstration, les livreurs en course avancent de façon simulée.

## Suivi client en direct et avis (inspiré des applications de livraison)
Dans le détail d'une commande, **📡 Lien de suivi client** : le client ouvre une page (sans compte) qui montre l'avancement en 6 étapes avec les heures, le **prénom du livreur**, l'**heure d'arrivée estimée**, la **carte avec la position du livreur pendant la course** et le montant à régler ; la page se met à jour toute seule. Le code de confirmation n'y figure jamais (il reste dans le message au client). Après la livraison, le client **note de 1 à 5 étoiles** et peut laisser un commentaire (un seul avis par livraison, non modifiable). Les avis alimentent la colonne *Avis clients* des livreurs, le tableau de bord (*Satisfaction client*) et l'écran du livreur. Le formulaire de commande affiche aussi le **délai de livraison estimé** de la zone. En démonstration le lien fonctionne sur le même appareil ; en mode connecté (migration `20261014000000_suivi_client.sql`), il contient un secret de 256 bits et fonctionne partout.

## Dossiers des livreurs
Menu *Livreurs & motos* → **📁 Dossier** : photo, pièce d'identité (recto/verso), permis, personne à prévenir, garant, accord du livreur ; les photos sont réduites dans le navigateur. Statut *Dossier complet / À compléter*, alertes sur le tableau de bord (dossier incomplet, échéance à 30 jours), et option *Paramètres → Exiger un dossier complet avant toute affectation*. En démonstration, les images restent dans le navigateur (le livreur Issa a un dossier-spécimen) ; en mode connecté, elles sont stockées côté serveur avec accès restreint (administrateur, superviseur, livreur concerné).

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

## Déploiement (Vercel)
Importer le dépôt dans Vercel : aucun réglage (Framework « Other », pas de build, dossier racine = racine). Le fichier `.vercelignore` exclut `supabase/` (sources du backend, non destinées à être publiques).
Attention : la page de connexion affiche les PIN de démonstration et les données restent dans le navigateur de chaque visiteur. C'est une démo, pas une mise en production : avant tout usage réel, brancher Supabase et retirer l'encart de démonstration.
