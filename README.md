# 🍺 AFRI-BAR Manager v2.1 — Guide de démarrage rapide

> Application monobloc HTML5 pour la gestion de **dépôts/concessionnaires de boissons** en Côte d'Ivoire.
> Conforme au cahier des charges + extensions **Ristournes** et **Facture 3 lignes DGI** v2.2 — Juin 2026

---

## 📦 Contenu de la livraison

| Fichier | Rôle |
|---|---|
| `AfriBar_Manager.html` | **L'application complète** (~180 Ko, tout-en-un) |
| `DEMARRER_AFRI_BAR.bat` | Lanceur Windows (serveur local Python sur port 8080) |
| `README.md` | Ce fichier |

**Zéro dépendance, zéro internet requis.** Persistance localStorage.

---

## 🚀 Démarrage en 3 secondes

- **Firefox** : double-clic sur `AfriBar_Manager.html` → ça marche directement
- **Chrome Windows** : double-clic sur `DEMARRER_AFRI_BAR.bat` (nécessite Python)
- **Android** : héberger sur un PC du même Wi-Fi, ouvrir avec Chrome mobile
- **Production** : upload sur n'importe quel serveur statique (Netlify, OVH...)

---

## ✅ Modules livrés

| # | Module | Fonctionnalités clés |
|---|---|---|
| 📊 | **Tableau de bord** | 8 KPI temps réel, graphe CA 7j, alertes prioritaires consolidées, actions rapides |
| 🏭 | **Concessionnaires** | NIF + agrément + territoire (SOLIBRA, SIFCA, Import Elite) |
| 📦 | **Fournisseurs** | Fournisseurs annexes (emballages, glace, consommables) |
| 🛒 | **Achats / Entrées** | Saisie BL, lignes multiples, MAJ stock auto |
| 🔁 | **Transferts inter-dépôts** | BL, prix de transfert, mouvements out/in |
| 🍺 | **Articles** | Modèle unifié **liquide + bouteille + casier** |
| 📦 | **Stock unifié** | 3 composants synchronisés, seuils, alertes |
| 📜 | **Journal mouvements** | Historique filtré par type (achat/vente/transfert/retour/perte/ajustement) |
| 🧾 | **Inventaire physique** | Saisie écart, ajustement automatique du stock |
| 👥 | **Clients** | NIF, type, solde et consignation visibles en un coup d'œil |
| 🧾 | **Factures FNE** | Format DGI CI complet : NIF, HT/TVA/TTC, **montant en lettres**, QR, impression, **partage WhatsApp** |
| 💰 | **Encaissements** | 7 modes : Espèces, Wave, OM, MTN, Moov, Chèque, Virement |
| 🚨 | **Surveillance emballages** | Alertes **3j🟠 / 7j🔴**, badge nav, valeur exposée, appel direct, signalement perte, retour différé |
| 🎁 | **🆕 Ristournes** | **Module complet** : 4 types × 2 directions × 3 modes — voir détail ci-dessous |
| 🌐 | **Réseau distribution** | Vue hiérarchique 4 niveaux |
| 🏬 | **Dépôts & sous-dépôts** | Gestion hiérarchique |
| ⚙️ | **Paramétrage** | 6 sections (identité, FNE, seuils, modes paiement, export, zone danger) |

---

## 🎁 Module Ristournes (extension v2.1)

Conçu pour les utilisateurs qui sont **à la fois concessionnaires** (recevant des ristournes des brasseurs) **et grossistes** (accordant des ristournes à leurs propres dépôts/clients).

### 4 types de ristournes gérés par contrat

| Type | Description | Configurable |
|---|---|---|
| 📊 **Volume / Palier** | % du CA HT (ou F/casier) avec paliers progressifs (ex : 0–500k=0%, 500k–2.5M=1.5%, 2.5M+=3%) | base + paliers illimités |
| 🎯 **Objectif** | Forfait fixe si l'objectif (casiers ou CA) est atteint dans la période | objectif + bonus |
| ⏱ **Escompte comptant** | % du HT si paiement dans le délai (ex : 1.5% sous 7 jours) | délai + taux |
| 🎁 **Bonus nature** | X casiers offerts pour Y casiers achetés (ex : 1 pour 50) | seuil + casiers offerts |

### 2 directions

- ⬇️ **Reçue** : contrat avec un concessionnaire (calcul sur vos achats chez lui)
- ⬆️ **Accordée** : contrat avec un dépôt/sous-dépôt/client (calcul sur vos ventes ou transferts vers lui)

La direction est déterminée automatiquement par le type de partenaire choisi.

### 3 modes d'application (configurables PAR contrat)

- **Avoir sur facture suivante** (le plus courant)
- **Avoir en compte cumulé** (à utiliser quand vous voulez)
- **Virement séparé fin de période**

→ vous gérez le « mix selon le concessionnaire » de votre cas.

### Calcul automatique

- Recalcul **à chaque ouverture du module** ou via le bouton 🔄
- Calcule la **période courante ET précédente** (pour voir les ristournes acquises mais pas encore appliquées)
- Périodes : mensuelle / trimestrielle / annuelle
- Le tableau de bord affiche **Ristournes nettes (reçues − accordées)** → indicateur de marge réelle

### Données démo fournies

5 contrats pré-configurés :
1. **SOLIBRA** (reçue, mensuelle) : volume 4 paliers % du CA + escompte 1.5% à 7j → mode avoir facture
2. **SIFCA** (reçue, mensuelle) : volume 3 paliers % du CA + objectif 1.5M / 50k bonus + 1 casier offert tous les 50 → mode avoir compte
3. **Import Elite** (reçue, trimestrielle) : 1% sur tout le CA + 2% escompte comptant → mode virement séparé
4. **Sous-dépôt Yopougon** (accordée, mensuelle) : palier casiers + objectif 150c / 25k bonus → mode avoir facture
5. **Sous-dépôt Marcory** (accordée, mensuelle) : escompte 1% à 3j → mode avoir facture

---


---

## 🧾 Structure facture conforme DGI (v2.2)

Chaque produit récupérable génère **3 lignes** sur la facture FNE :

| Ligne | Désignation | Quantité | P.U. | TVA |
|---|---|---|---|---|
| 1 | **💧 Liquide** (le contenu) | en bouteilles | prix btl | ✓ 18% |
| 2 | **🍺 Bouteilles vides consignées** | en bouteilles | consigne btl (ex 25 F) | hors TVA |
| 3 | **🧺 Casier vide consigné** | en casiers | consigne casier (ex 300 F) | hors TVA |

Les produits **perdus** (canettes, vins importés) génèrent 1 seule ligne (liquide).

**Conformité DGI** : la consigne d'emballage récupérable n'est pas soumise à la TVA (dépôt de garantie remboursable). Seul le liquide est taxable.

**Retour à la livraison** : saisi globalement, alloué FIFO aux consignations actives, affiché en ligne d'avoir négatif sur la facture.

Exemple — Facture 2 casiers de Flag, aucun retour :

```
💧 Flag 65cl — Liquide                    24 btl × 600 F = 14 400 F  [TVA]
🍺 Bouteilles vides consignées — Flag     24 btl ×  25 F =    600 F  [hors]
🧺 Casiers vides consignés — Flag          2 cas × 300 F =    600 F  [hors]
                                                            ─────────
                                          Liquide HT            14 400 F
                                          TVA 18%                2 592 F
                                          Consigne emballages    1 200 F
                                          ────────────────────────────
                                          TOTAL TTC             18 192 F
```

**Consignation client** : pour chaque produit récupérable, une consignation active est créée avec le montant **plein** facturé. Elle est ensuite réduite par les retours (à la livraison ou différés). Tant que reste > 0, l'alerte 🟠/🔴 s'applique.
## 🧺 Gestion des emballages (cœur du métier)

Modèle unifié 3 composants : 💧 Liquide + 🍺 Bouteille (consignée 25 F) + 🧺 Casier (consigné 300 F).

À la facturation : calcul automatique des emballages attendus, saisie des rapportés, calcul déficit, intégration consignation. 3 scénarios couverts (retour complet / partiel / aucun).

Surveillance : alertes 🟠 à 3 jours / 🔴 à 7 jours, badge rouge dans la nav, bouton appel direct.

---


---

## 🚚 Module Livraison (v2.3 — nouveau)

Chaîne complète : badge client → tournée → bordereau → mode livreur → réconciliation.

### 🪪 Badges clients

**Génération automatique** d'un code unique par client à la création :
- Format : 3 lettres du nom + tiret + 3 chars hex (ex : `BUV-9UE` pour Buvette Chez Marie)
- Identicon visuel symétrique unique par client (pour identité visuelle de la carte)
- Carte format **74 × 52 mm** (carte fidélité standard) imprimable depuis la vue 🪪 Badges
- Le client garde le badge dans son établissement
- Coût d'impression : ~50 F dans un cybercafé

→ Vue **🪪 Badges clients** : grille de toutes les cartes, clic = impression individuelle, bouton « Imprimer tous » pour planche de cartes A4

### 🚚 Tournées de livraison

Workflow en 4 phases (statut visible en temps réel) :

| Phase | État | Actions |
|---|---|---|
| 1. Préparation | 📋 Préparée | Créer, ajouter livraisons (= factures), imprimer BL |
| 2. Départ | 🚦 En cours | Le livreur effectue les livraisons une par une |
| 3. Retour | ⏳ Terminée | Tournée close, en attente réconciliation manager |
| 4. Réconciliation | ✓ Réconciliée | Cash physique compté, vides comptés, écart calculé, validation |

Chaque tournée contient :
- Livreur (sélection dans `STATE.config.livreurs`)
- Véhicule (Tricycle, Scooter, Pick-up, Camion, À pied)
- Zone (texte libre, ex : « Yopougon + Treichville »)
- Liste de livraisons liées à des factures existantes

### 🧾 Bordereau de Livraison (BL)

**Document de transport distinct de la facture FNE** :
- Format A4 imprimable, structuré par client
- Inclut : nom + code badge, articles à livrer, vides à reprendre, montant TTC
- Zone de signature contradictoire (livreur + client)
- Mention explicite : « Document non fiscal, sert de bon de transport »
- La facture FNE reste le seul document fiscal

→ Bouton « 🖨 Imprimer BL » sur la vue détail tournée

### 📱 Mode livreur

**Interface dédiée**, simplifiée pour usage terrain :
- Bouton « Identifier client » avec saisie code badge **gros et clair** + sélection dans la liste tournée en fallback
- Carte par client à livrer (gros titre, code badge mis en valeur, prix, lien appel direct)
- Header noir avec stats temps réel : Livrés / Encaissé / Vides
- Card cliquable → modal « Effectuer livraison » avec 4 statuts : ✓ Livré · ⚠ Partiel · ❌ Absent · 🚫 Refusé
- Saisie consolidée : vides rapportés + encaissement (7 modes) + note + référence

→ Vue **📱 Mode livreur** affiche la tournée du jour en cours automatiquement

### ✓ Réconciliation fin de tournée

À la fermeture, le manager saisit :
- **Cash physique compté** (espèces seulement) → écart caisse calculé automatiquement (positif = cash en plus, négatif = manquant)
- **Vides physiques comptés** (vs déclarés par livreur)
- Note de réconciliation libre

L'écart est mis en valeur en couleur (🔴 si négatif). La tournée passe en statut « ✓ Réconciliée » avec historique complet (créée, démarrée, terminée, réconciliée).

### Workflow type d'une journée

```
07h00 — Manager au dépôt
  └─ Crée tournée TRN-20260603-01 (Issa, tricycle, zone Yopougon)
  └─ Ajoute 8 factures à livrer (clients connus, montants pré-saisis)
  └─ Imprime BL → remet au livreur

08h00 — Issa démarre
  └─ Tournée en_cours
  └─ Charge le tricycle avec articles + vides à reprendre

09h-15h — Sur le terrain (Issa, app mode livreur)
  └─ Arrive chez "Buvette Chez Marie"
  └─ Scanne (ou tape) code BUV-9UE → modal s'ouvre
  └─ Confirme livraison · saisie vides rapportés · Wave 18 192 F
  └─ Validation → passe au client suivant
  └─ 7 autres livraisons + 1 absent (reporté)

15h30 — Retour dépôt
  └─ Issa : "Terminer la tournée"
  └─ Statut = terminée

16h00 — Manager réconcilie
  └─ Compte cash physique : 80 200 F vs prévu 80 000 F → +200 F (pourboires)
  └─ Compte vides physiques : 32c + 280b conformes
  └─ Validation → Réconciliée ✓
```

### Limitations actuelles (Phase 1 prototype)

| Fonctionnalité | État | Phase 2 |
|---|---|---|
| Badges 6 chars + identicon | ✓ Implémenté | + Vrai QR code scannable |
| Saisie manuelle du code | ✓ Implémenté | + Scanner caméra |
| Bordereau imprimable | ✓ Implémenté | + Signature numérique sur tablette |
| Mode livreur simplifié | ✓ Implémenté | + Auth livreur séparée + sync cloud |
| Réconciliation cash+vides | ✓ Implémenté | + Photos justificatives |

---

## ↩ Module Retours marchandise (v2.4 — nouveau)

Distinct du retour d'emballages vides : ce module gère la **reprise de produits livrés non vendus**, avec génération d'un **avoir FNE**, gestion fiscale conforme DGI, et option de **réaffectation directe à un autre client en urgence**.

### Le scénario type

Un client (ou sous-dépôt) est livré sur crédit (BL + facture émise non payée). Il n'arrive pas à écouler la marchandise. Vous avez **besoin urgent** de ces produits pour un autre client. L'app gère :
1. La saisie du retour (total ou partiel, ligne par ligne)
2. La génération d'un **avoir FNE** (document fiscal miroir de la facture)
3. La **réaffectation immédiate** facultative à un autre client (nouvelle facture FNE créée automatiquement)
4. La mise à jour cascade : stock, facture origine, consignations, ristournes

### Document AVOIR FNE (format DGI)

L'avoir respecte la pratique fiscale DGI :
- Numérotation distincte : `AV-2026XXX`
- Référence obligatoire à la facture origine
- Structure 3 lignes par produit (en miroir négatif de la facture)
- TVA aussi créditée (sur le liquide uniquement)
- Mention claire « AVOIR DE RETOUR — en miroir de FNE-XXX »
- Montant en lettres

### Les 3 décisions par retour (toutes flexibles)

**1. Consigne reprise ou pas ?** (par ligne d'article)
- ☑ Cochée par défaut → la consigne (vides) est aussi remboursée, la consignation associée est soldée. Cas typique : casier(s) rendu(s) PLEIN(S) et fermé(s).
- ☐ Décochée → seul le liquide est remboursé, le client garde les vides et la consignation reste active.

**2. Destination des produits récupérés**
- 🏬 **Stock du dépôt** → réintégration au stock liquide. Stock = +qty retournée
- 🔁 **Réaffectation directe à un autre client** (votre cas urgence !) → une nouvelle facture FNE est émise immédiatement pour le client B avec ces produits. Net sur le stock = 0 (entrée+sortie simultanées). Traçabilité totale entre les 3 documents (facture A → avoir → facture B)

**3. Mode d'application de l'avoir**
- 📌 **Déduction du reste à payer** de la facture origine (par défaut)
- 💼 **Avoir en compte client** (cumul utilisable pour une future facture)
- 🏦 **Remboursement effectif** (cash / Wave / OM... — rare)

### Workflow type

```
Lundi   : Livraison à crédit chez Grossiste KTL : 10 casiers Flag (FNE-2026003 · 129 360 F)
Mardi   : Grossiste appelle "je n'arrive pas à vendre 3 casiers"
Mardi+1 : Buvette du Carrefour téléphone : "j'ai un événement, j'ai besoin urgent de Flag"

Dans l'app :
  1. Ouvrir FNE-2026003 → bouton "↩ Retourner produits"
  2. Indiquer 3 casiers Flag, consigne reprise ☑
  3. Destination : 🔁 Réaffectation → choisir Buvette du Carrefour
  4. Application : 📌 Déduction du reste à payer
  5. Motif : ⚡ Urgence autre client
  6. Validation

Effets automatiques :
  • Avoir AV-2026001 émis : −27 288 F
  • Facture FNE-2026003 : TTC ajusté à 102 072 F, reste à payer 52 072 F
  • Nouvelle facture FNE-2026008 pour Buvette du Carrefour : 27 288 F (impayée)
  • Stock Flag : inchangé (transfert logique A → B)
  • Consignation Grossiste : réduite de 3c+36b
  • Nouvelle consignation Buvette Carrefour : 3c+36b
  • Mouvement "retour_marchandise" + mouvement "vente" tracés
  • Ristournes recalculées sur les nouveaux CA HT
```

### Tests mathématiques vérifiés

Scénario réaffectation directe (vérifié end-to-end) :
- Stock liquide initial Flag : 696 btl
- Retour de 3 casiers + réaffectation à client B
- Stock final : **696 btl (delta 0)** — la marchandise est passée directement de A à B sans transit physique

Scénario retour total au stock :
- Stock initial : 696 btl
- Retour total facture Buvette (2 casiers Flag = 24 btl)
- Stock final : **720 btl (delta +24)** — marchandise réintégrée

Recalcul ristournes : automatique après chaque retour (le CA HT baisse, les ristournes accordées/reçues sont ajustées).
## 🎨 Charte graphique respectée

`#0F8A5F` Vert Émeraude · `#F28C28` Orange Énergie · `#1D3557` Bleu Nuit · `#DC2626` Rouge. Mobile-first avec sidebar PC + bottom-nav Android (breakpoint 768px).

---

## 📲 Conformité Côte d'Ivoire

- ✅ **Facture Normalisée Électronique (FNE)** : format DGI CI complet
- ✅ **Mobile Money** : Wave, Orange Money, MTN MoMo, Moov Money + Ristourne pré-configurés
- ✅ **Hors ligne** : `localStorage` avec fallback mémoire
- ✅ **Mobile-first** : touch targets ≥ 44px, bottom nav

---

## 💾 Sauvegarde

Auto après chaque action. Export manuel : Paramétrage → Export JSON ou CSV. Reset démo : bouton 🔄 en haut.

**💡 Conseil** : exportez le JSON chaque fin de journée pour archivage.

---


---

## 📦 Données de démonstration (rechargeable via 🔄)

Au premier lancement (ou après reset), le système se peuple avec un jeu de données réaliste reflétant 3 jours d'activité.

### Tournées (3)

| N° | Date | Livreur | Véhicule | Zone | Statut | Détail |
|---|---|---|---|---|---|---|
| TRN-...0530 | J-2 | Issa Traoré | Tricycle | Yopougon + Treichville | ✓ Réconciliée | 4/4 livrées · 57 702 F encaissés (Wave + Espèces) · 7c+90b vides · écart 0 |
| TRN-...0531 | J-1 | Aboubacar Konaté | Pick-up | Cocody + Marcory | ✓ Réconciliée | 3/4 livrées + 1 absent · 137 352 F · +500 F pourboires |
| TRN-...0601 | Auj. | Sékou Camara | Tricycle | Plateau + Treichville | 📋 Préparée | 4 livraisons impayées prêtes à démarrer |

### Retours marchandise (3) — couvrent les 3 cas business

| N° | Motif | Client | Destination | Application | Montant |
|---|---|---|---|---|---|
| AV-2026001 | ⚡ Urgence autre client | Grossiste KTL | 🔁 Réaffectation → Buvette du Carrefour (nouvelle FNE) | 📌 Déduction facture | −27 288 F |
| AV-2026002 | 📉 Invendu | Restaurant Saveurs d'Ici (vins + Corona perdus) | 🏬 Stock | 💼 Avoir compte | −77 880 F |
| AV-2026003 | ❌ Défectueux | Maquis La Référence (Malta) | 🏬 Stock | 🏦 Remboursement Wave | −12 058 F |

### Volumétrie totale au démarrage

- **16 factures** (3 lignes par produit récupérable, structure FNE complète)
- **12 encaissements** (mix Wave, Espèces, Orange Money sur historique)
- **8 consignations actives** (sur factures impayées et historique non totalement repris)
- **3 tournées** dont 1 préparée à démarrer
- **3 avoirs** illustrant les 3 modes d'application
- **5 contrats de ristournes** (3 reçues SOLIBRA/SIFCA/Elite + 2 accordées sous-dépôts)
- **5 transferts** inter-dépôts + **5 achats** concessionnaires
- **8 clients** avec badges générés automatiquement
- **8 articles** (5 récupérables + 3 perdus)
- **6 mouvements de stock** par catégorie (achat/vente/transfert/retour_emballage/retour_marchandise/ajustement)

### Cas business démonstrés

✅ Vente complète (livraison du jour + paiement)  
✅ Vente à crédit (livré, non payé)  
✅ Vente partiellement payée (acompte)  
✅ Retour total emballages à la livraison (Hôtel Akwaba)  
✅ Retour partiel emballages (Supérette)  
✅ Vente btl vrac sans casier (Bar Tropical)  
✅ Vente produits perdus uniquement (Restaurant)  
✅ Tournée historique réconciliée (cash compté, écart calculé)  
✅ Client absent à la livraison (reporté)  
✅ Pourboires en cash (écart caisse positif)  
✅ **Réaffectation urgence A → B** (votre cas métier)  
✅ Retour total invendu → avoir compte client  
✅ Retour produit défectueux → remboursement Mobile Money  
✅ Consignation soldée par retour marchandise (consigne reprise)  
✅ Ristournes calculées en cascade sur tous les CA modifiés
## 🛣 Roadmap Phase 2 (selon cahier des charges)

1. Migration React + Node.js + PostgreSQL (3 mois, 5.4M F CFA)
2. Auth JWT 3 rôles, PWA Service Worker, API Wave/OM/MTN, certification FNE auto
3. App Android native, alertes WhatsApp Business API, multi-dépôts centralisés

---

**🍺 AFRI-BAR Manager v2.1** · Mobile-first · Offline-first · Made for 🇨🇮
