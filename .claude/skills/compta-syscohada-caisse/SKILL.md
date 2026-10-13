---
name: compta-syscohada-caisse
description: Comptabilité SYSCOHADA révisé (OHADA, FCFA) et gestion de caisse pour DISTRIPRO-ERP. À utiliser pour générer automatiquement les écritures comptables (journaux, grand livre, balance, brouillard de caisse, rapprochement Mobile Money, TVA) à partir des tables fonds, depenses, reglements_vendeurs, paiements_livreurs, stock_mouvements, ou pour concevoir/modifier ce module (migrations Supabase, RPC, écrans).
---

# Comptabilité SYSCOHADA + Caisse (DISTRIPRO-ERP)

Objectif : chaque opération métier déjà saisie dans l'ERP produit **automatiquement** une écriture
comptable équilibrée, sans ressaisie. La caisse (espèces + Mobile Money) est le point d'entrée.

## Principes non négociables
1. **Partie double** : total débit = total crédit pour chaque pièce. Refuser toute écriture déséquilibrée côté serveur.
2. **Montants en entiers FCFA** (pas de décimales), comme `montant int` dans le schéma actuel.
3. **Journaux en ajout seul** : une erreur se corrige par une écriture d'extourne (contre-passation), jamais par UPDATE/DELETE. Même philosophie que `stock_mouvements`.
4. **Clôture de période** : une période clôturée refuse toute nouvelle écriture datée dedans.
5. **Numérotation continue et sans trou** des pièces par journal et par exercice (utiliser `app.next_num`-style compteur par journal).
6. **Traçabilité** : chaque écriture référence sa source (`source_table`, `source_id`) et l'auteur (`par`, `par_nom`), et passe par `audit_log`.
7. **Multi-organisation** : `org_id` partout, RLS identique aux autres tables ; écriture uniquement via RPC `security definer` (convention du projet, voir `supabase/README.md`).
8. Aucun solde ne se « saisit » : tout est recalculé depuis les écritures.

## Journaux
| Code | Journal | Alimenté par |
|---|---|---|
| CAI | Caisse espèces | encaissements livreurs, reversements, dépenses payées en espèces |
| MM | Mobile Money | versements/encaissements Mobile Money (référence unique obligatoire) |
| VT | Ventes | commande livrée |
| AC | Achats | `recevoir_stock` |
| OD | Opérations diverses | inventaire, extournes, régularisations |
| RAN | À-nouveaux | report à l'ouverture d'exercice |

## Plan de comptes utilisé (SYSCOHADA révisé, extrait)
Voir `references/plan-comptable.md` pour la liste complète et les comptes par défaut.

## Matrice d'écritures automatiques
Voir `references/ecritures-automatiques.md`. Résumé :

| Événement DISTRIPRO | Débit | Crédit |
|---|---|---|
| Commande livrée (vente) | 411 Clients | 701 Ventes + 4431 TVA collectée |
| Encaissement livreur (espèces) | 5711 Caisse livreur / 571 | 411 Clients |
| Encaissement Mobile Money direct | 5121/5131 Mobile Money | 411 Clients |
| Reversement du livreur à la caisse | 571 Caisse principale | 5711 Caisse livreur |
| Dépense livreur (carburant…) | 6xx selon nature | 571 / 4211 |
| Commission livreur payée | 661 Rémunérations | 571 |
| Règlement vendeur | 401 Fournisseurs/vendeurs | 571 ou Mobile Money |
| Entrée de stock | 601 Achats (ou 31 Stocks) + TVA déductible | 401 / 571 |
| Écart d'inventaire | 603 Variation de stocks / 658 | 31 Stocks |
| Écart de caisse (livreur) | 658 ou 758 | 5711 / 411 |

## Fonctionnement de la caisse
- **Brouillard de caisse** quotidien : solde d'ouverture, encaissements, décaissements, solde théorique, **comptage physique**, écart, justification obligatoire de l'écart.
- **Clôture de caisse** par caissier (verrouille la journée, génère l'OD d'écart).
- **Une caisse = un compte 57x** ; une caisse par livreur (sous-compte 5711…) permet de suivre le fonds détenu, cohérent avec `solde_livreurs()`.
- **Mobile Money** : rapprochement entre l'export CSV existant et le relevé opérateur, par référence ; écarts listés, jamais lissés.
- Plafond d'espèces et alerte de solde négatif (une caisse ne peut jamais être créditrice).

## États produits
Journal par journal, **grand livre**, **balance générale** (6 colonnes), **balance âgée clients/vendeurs**, **état de TVA**, brouillard de caisse, puis (phase 2) bilan et compte de résultat SYSCOHADA. Export CSV et impression, comme les états de stock existants.

## Méthode de travail
1. Lire `supabase/README.md` et le schéma avant toute modification ; ne jamais contourner les RPC.
2. Créer une **nouvelle migration** datée (ne pas modifier les anciennes) : tables `comptes`, `journaux`, `ecritures`, `ecriture_lignes`, `periodes`, `caisse_cloture`.
3. Générer les écritures par **triggers/RPC** sur les tables sources, jamais côté navigateur.
4. Écrire les tests SQL dans `supabase/tests/test_compta.sql` (équilibre, extourne, clôture, isolation entre organisations) sur le modèle de `test_versements.sql`.
5. Ajouter les écrans dans `index.html` en suivant le style des pages Finance et Journal des mouvements.
6. Mettre à jour `README.md` (fonctionnalités) et `supabase/README.md` (migration, RPC, tests).

## Points à valider avec le comptable avant d'implémenter
- Régime d'imposition et taux de TVA du pays (18 % en Côte d'Ivoire, 19,25 % au Cameroun, etc.).
- Stock tenu en inventaire permanent ou intermittent.
- Les ventes sont-elles reconnues à la livraison ou à l'encaissement ?
- Commission du livreur : charge de personnel ou prestation externe ?
- Les montants du plan de comptes par défaut sont des **valeurs de départ** à faire valider par un expert-comptable : ce skill n'est pas un avis comptable ou fiscal.
