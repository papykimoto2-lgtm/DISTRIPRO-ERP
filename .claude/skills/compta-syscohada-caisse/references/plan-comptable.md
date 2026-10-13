# Plan de comptes par défaut (SYSCOHADA révisé, extrait pour distribution)

À faire valider par l'expert-comptable de l'organisation. Chaque organisation peut ajouter des sous-comptes.

| Compte | Libellé | Usage dans DISTRIPRO |
|---|---|---|
| 31 | Marchandises (stocks) | valorisation via `produits.cout` |
| 401 | Fournisseurs (dont vendeurs) | montants dus aux vendeurs |
| 4011 | Vendeurs partenaires | `reglements_vendeurs` |
| 411 | Clients | créances sur commandes livrées |
| 4211 | Personnel, avances et acomptes | `paiements_livreurs` type avance |
| 4431 | TVA facturée sur ventes | |
| 4452 | TVA récupérable sur achats | |
| 511 | Chèques à encaisser | si utilisé |
| 5121 | Banque | |
| 5131 | Mobile Money (opérateur) | encaissements/versements MM |
| 571 | Caisse principale | espèces siège |
| 5711 | Caisses livreurs (sous-compte par livreur) | fonds détenus |
| 585 | Virements de fonds (compte d'attente) | transferts caisse/MM en cours |
| 601 | Achats de marchandises | |
| 603 | Variations de stocks | |
| 6241 | Transports/livraisons | carburant, frais de course |
| 661 | Rémunérations directes | commissions livreurs |
| 658 | Charges diverses (écarts de caisse négatifs) | |
| 701 | Ventes de marchandises | |
| 706 | Services vendus (frais de livraison) | `commandes.frais` |
| 758 | Produits divers (écarts de caisse positifs) | |

Contrôles de cohérence : classe 4 (tiers) soldée par tiers, classe 5 (trésorerie) jamais créditrice, classes 6/7 remises à zéro à la clôture de l'exercice.
