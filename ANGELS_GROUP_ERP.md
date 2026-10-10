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
| Rôles, désactivation immédiate d'un compte, journal d'audit | ✅ |
| Incidents et réclamations | ✅ |

## Limites assumées (à traiter avant production)
- **Données stockées dans le navigateur d'un seul appareil.** Pour que le bureau et les téléphones des livreurs partagent les données, il faut un backend (Supabase/PostgreSQL, cahier des charges §17) avec authentification et règles d'accès **côté serveur**. Ici les droits ne sont appliqués que dans l'interface : ce n'est pas une sécurité.
- Les PIN sont hachés de façon simple (démonstration) ; le journal d'audit n'est pas inviolable.
- GPS en arrière-plan écran éteint non garanti en page web : à valider sur les téléphones réels, sinon application native.
- Notifications SMS/WhatsApp : seul un lien WhatsApp pré-rempli pour le code client est fourni.
- Facturation normalisée/fiscale, tournées optimisées, suggestions automatiques d'affectation, gestion des motos (rentabilité, entretien détaillé) : V2/V3.
