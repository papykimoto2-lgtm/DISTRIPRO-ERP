# Écritures automatiques : source → journal → comptes

Montants en FCFA entiers. Le HT et la TVA se calculent sur le TTC avec le taux de l'organisation (arrondi, l'écart d'arrondi va dans la ligne TVA).

## 1. Commande livrée — journal VT
Source : `commandes` passant à `livree`.
```
D 411 Clients                         total TTC (articles + frais - remise)
  C 701 Ventes de marchandises        HT articles
  C 706 Services vendus               frais de livraison HT
  C 4431 TVA facturée                 TVA
```
Si `vendeur_encaisse = true` (articles déjà payés au vendeur) : pas de créance sur les articles, seulement sur les frais.

## 2. Encaissement livreur — journal CAI ou MM
Source : `fonds.type in ('acompte','encaissement')`.
- Espèces : `D 5711 Caisse livreur` / `C 411 Clients`
- Mobile Money direct : `D 5131 Mobile Money` / `C 411 Clients` (référence unique = `ref` de la pièce)
Écart d'encaissement (`livraisons.ecart`) : `D/C 658 ou 758` contre `411`.

## 3. Reversement — journal CAI
Source : `fonds.type = 'reversement'`.
```
D 571 Caisse principale
  C 5711 Caisse du livreur
```
Pour un versement Mobile Money validé par le caissier : `D 5131` / `C 5711` (ou `C 411` si paiement direct).

## 4. Dépenses du livreur — journal CAI
Source : `depenses` (nature → compte, voir table de correspondance ci-dessous).
```
D 6241 (ou compte selon nature)
  C 5711 Caisse du livreur
```
| nature (mot-clé) | Compte |
|---|---|
| carburant, essence, transport | 6241 |
| réparation, entretien moto | 6242 (à créer) |
| autre | 658 |

## 5. Paiements aux livreurs — journal CAI
Source : `paiements_livreurs`.
- `commission` : `D 661` / `C 571`
- `avance` : `D 4211` / `C 571`

## 6. Règlement vendeur — journal CAI ou MM
Source : `reglements_vendeurs`.
```
D 4011 Vendeurs partenaires
  C 571 (espèces) ou 5131 (Mobile Money selon `mode`)
```
Les ventes pour compte de vendeur ne sont comptabilisées en 401 qu'au prorata des articles livrés non encore réglés (cohérent avec la logique « articles déjà payés au vendeur »).

## 7. Entrée de stock — journal AC
Source : `recevoir_stock` (référence BL obligatoire = `ref`).
```
D 601 Achats de marchandises   coût HT
D 4452 TVA récupérable         TVA
  C 401 Fournisseurs (ou 571)  TTC
```
En inventaire permanent : `D 31` au lieu de `D 601`.

## 8. Inventaire — journal OD
Source : `valider_inventaire`, par écart valorisé au coût.
- Manquant : `D 603 / 658` ; `C 31`
- Excédent : `D 31` ; `C 603 / 758`

## 9. Clôture de caisse — journal CAI
Écart entre solde théorique et comptage :
- Manque : `D 658` / `C 571`
- Excédent : `D 571` / `C 758`
Justification obligatoire ; sans justification la clôture est refusée.

## 10. Extourne
Toute correction = écriture inverse liée à l'originale (`extourne_de`), puis nouvelle écriture correcte. Jamais de modification.
