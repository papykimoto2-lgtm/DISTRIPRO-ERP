# Modèle ImmoSuite à reproduire dans DISTRIPRO

Source : `papykimoto2-lgtm/ImmoSuite-ERP` (`index.html`, fonctions `caisse*`, `genererEcriture*`, `ecr*`, `buildBalance`, `buildGrandLivre`). Ici on reprend la **logique**, pas le code : ImmoSuite stocke tout côté navigateur (IndexedDB + synchro), DISTRIPRO doit tout faire en SQL/RPC côté serveur.

## 1. Cycle de vie d'une caisse (à reproduire)
1. **Caisse** = compte 57x + division/agence + caissier(s) + option `requiert_validation`.
2. **Session** (ouverture) : fond d'ouverture = fond de clôture réel de la session précédente. Ajustement de fond d'ouverture tracé.
3. **Mouvement / bon** (`entree` | `sortie`) : numéro séquentiel (`BC-…`), motif, bénéficiaire, pièce justificative. Si montant > plafond du rôle → `requiert_validation` et **aucune écriture tant que non approuvé** (entrée comme sortie).
4. **Décaissement en deux temps** : demande → validation par un responsable → décaissement (`caisseValiderDecaissement`, `caisseRejeterDecaissement`).
5. **Clôture** : solde théorique vs comptage réel, écart = réel − théorique. Règles :
   - comptage jamais négatif ;
   - solde théorique négatif = alerte forte et confirmation explicite ;
   - plafond de validation du rôle contrôlé sur le solde **de la session clôturée** (piège corrigé dans ImmoSuite : ne pas contrôler la première session venue) ;
   - la clôture fige la session.
6. **Ventilation** (affectation comptable d'un mouvement clos) : manuelle, ou **automatique par règles de mots-clés sur le motif** → compte de contrepartie. Les écritures auto sont marquées `ventile_auto` pour pouvoir **annuler en masse** une règle mal configurée.
7. **Régularisation d'écart** : écriture `ECART-AAAAMMJJ` : excédent `D 57x / C 758`, manquant `D 658 / C 57x`. Si l'écriture est refusée (exercice clos), l'écart **reste** à régulariser.
8. **Instantané (snapshot)** avant toute opération de masse (ventilation auto, import CSV) avec restauration possible.

## 2. Écriture comptable
- Une écriture = pièce multi-lignes (`sens` D/C, `compte`, `montant`) ; équilibre vérifié (écart < 1 FCFA) et **bloquant au visa**.
- **Statut brouillard → validée (visa)**. Une saisie manuelle non visée **n'entre pas** dans balance/bilan/résultat. Une écriture visée est immuable : correction par **contre-passation**.
- Les écritures automatiques (caisse, ventes, stock) sont définitives dès leur création (`origine_manuelle` faux).
- Contrôles avant visa : ligne sans compte, compte de regroupement (compte parent) interdit, déséquilibre, aucune ligne.
- **Type d'écriture déduit de la classe du contre-compte** : 6 → `charge`, 7 → `produit`, sinon `tresorerie`. Ne jamais figer le type à `actif` (bug réel d'ImmoSuite : charges absentes des tableaux de bord).
- Identifiant **déterministe par source** (`ecr_cse_<id mouvement>`, `ecr_ecart_<id session>`) : rejouer la génération met à jour au lieu de dupliquer (idempotence).
- **Ne pas marquer un objet source comme traité tant que l'écriture n'est pas confirmée** (bug réel : mouvement « ventilé » pointant vers une écriture refusée = trou comptable silencieux).
- **Exercice clos** : toute écriture datée dedans est refusée au niveau base de données.
- Numérotation `PRÉFIXE-AAAA-NNNN` par préfixe et par année ; ne jamais utiliser `count(*)+1` (collisions après suppression ou entre années). En SQL : table `compteurs` verrouillée `FOR UPDATE`, déjà utilisée par `app.next_num`.
- **Divisions / agences** : colonne `division` sur caisse et écriture, filtre par division dans tous les états.

## 3. Journaux observés dans ImmoSuite
`OD` opérations diverses · `AC` achats · `VE` ventes · `PA` paie · `AN` à-nouveaux · `ST` stock · `CLO` clôture · journaux auxiliaires `JL-SIGLE-AN-NNNNN`. Pour DISTRIPRO, retenir : CAI, MM, VT, AC, ST, OD, AN, CLO.

## 4. États à reproduire
- **Brouillard de caisse** par session et par période, impression PDF, envoi automatique journalier/mensuel par email.
- **Dashboard caisse** : jour / mois / année avec navigation par période (ancre), par division.
- **Balance âgée** clients (411) et fournisseurs (401), avec tranches d'âge.
- **Budgets de caisse** par compte/période avec alertes de dépassement.
- **Balance, grand livre** (avec intervalle), journal, bilan, compte de résultat, tous filtrables par année/journal/division, et n'incluant que les écritures définitives.
- **Contrôle d'intégrité** : mouvement « ventilé » sans écriture ; écriture de caisse orpheline ; écart de montant mouvement ↔ écriture ; mouvement sur session ou caisse inexistante ; chaîne de sessions (ouverture = clôture précédente) ; doublons de numéros ; sessions doublons.
- **Import CSV** de mouvements avec rapport d'anomalies et snapshot préalable.

## 5. Pièges déjà rencontrés (à ne pas refaire)
| Piège | Règle pour DISTRIPRO |
|---|---|
| Valider une opération sans vérifier le retour de l'écriture | Transaction SQL unique : écriture + changement de statut, ou rien |
| Type d'écriture figé | Déduit de la classe du compte |
| Contrôle de plafond sur la mauvaise session | Toujours sur l'objet traité |
| Fond d'ouverture négatif reporté en silence | Refuser ou alerter ; jamais de report négatif |
| `length+1` pour numéroter | Compteur par préfixe/année |
| Comptage négatif accepté | Contrainte `check (fond_reel >= 0)` |
