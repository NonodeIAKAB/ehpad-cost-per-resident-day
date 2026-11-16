# Dictionnaire de données

Toutes les tables produites par le projet, colonne par colonne.
Statut : ✅ produite · 🚧 à venir (spécifiée, pas encore générée).

Conventions :
- encodage UTF-8, séparateur `,`, une ligne d'en-tête ;
- identifiants et codes stockés en **texte** (les codes département `01`, `2A`, `971` gardent leur forme) ;
- montants en euros hors taxes, deux décimales ;
- dates au format ISO `AAAA-MM-JJ`.

---

## ✅ `data/reference/dim_site.csv`

Dimension des sites. Un EHPAD réel par ligne, tiré de FINESS+ puis rendu non identifiable.
Produite par `src/extract_finess_ehpad.py`.

| Colonne | Type | Description | Origine / règle |
|---|---|---|---|
| `site_id` | texte | Identifiant du site, `SITE_0001` à `SITE_0300` | Attribué après tri par département puis numéro FINESS ; stable pour une même archive et une même graine |
| `secteur` | texte | `privé lucratif` dans le panel par défaut | FINESS, agrégats du statut juridique de l'entité juridique |
| `departement` | texte | Code département (`01`, `2A`, `971`…) | FINESS, déduit du code officiel géographique |
| `departement_libelle` | texte | Nom du département | FINESS |
| `nb_lits_installes` | entier | **Dénominateur du CRJ.** Lits d'hébergement complet en service | Somme de `capacite_installee` des activités 924 (permanent) et 657 (temporaire), mode 11, statut 1. Voir D-003 |
| `annee_ouverture` | entier | Année d'ouverture | FINESS `date_ouverture` |
| `latitude`, `longitude` | décimal | Position arrondie à 0,01° (environ 1 km) | FINESS, WGS 84. Voir D-006 |

Clé primaire : `site_id`. Pas de nom ni de numéro FINESS (voir D-006).

## ✅ `data/reference/data_quality_report.csv`

Une ligne par établissement et par contrôle échoué, sur **tous** les EHPAD actifs de France, pas seulement le panel.
Ce fichier décrit la source publique : il garde donc le numéro FINESS.

| Colonne | Type | Description |
|---|---|---|
| `finess_et` | texte | Numéro FINESS de l'établissement |
| `check` | texte | Nom du contrôle échoué (liste ci-dessous) |

| Contrôle | Bloquant | Signification |
|---|---|---|
| `duplicate_finess_et` | oui | Le même établissement apparaît deux fois |
| `missing_position` | oui | Pas de latitude ou de longitude |
| `position_outside_mainland_bbox` | oui | Position hors de la métropole pour un département métropolitain |
| `missing_installed_capacity` | oui | Aucune ligne d'hébergement complet en service |
| `zero_installed_capacity` | oui | Capacité d'hébergement à 0 |
| `active_but_closing_date` | non | Établissement actif avec une date de fermeture |
| `position_computed_from_xy` | non | Latitude et longitude calculées depuis x/y par l'outil de conversion, pas fournies par l'ANS |

## ✅ `data/reference/extraction_summary.json`

Trace d'exécution : date, paramètres (`n`, `seed`, `secteur`, plafond par entité juridique), comptages à chaque étape du filtre, nombre d'anomalies par contrôle.

## ✅ `data/reference/MENTION-SOURCE.txt`

Producteur (ANS), licence (Licence Ouverte 2.0), date de l'instantané FINESS+ utilisé. Obligatoire pour la réutilisation.

---

## 🚧 `fact_sales` – ventes mensuelles

Grain : un site × un article × un mois. Données **synthétiques**.

| Colonne | Type | Description |
|---|---|---|
| `site_id` | texte | Clé vers `dim_site` |
| `account_id` | texte | Compte de facturation du site |
| `sku` | texte | Clé vers `dim_product` |
| `month` | date | Premier jour du mois |
| `quantity` | décimal | Quantité facturée (négative pour un avoir) |
| `net_invoice_value` | décimal | Chiffre d'affaires net, en euros (négatif pour un avoir) |

## 🚧 `dim_product` – articles

| Colonne | Type | Description |
|---|---|---|
| `sku` | texte | Code article |
| `product_family` | texte | Famille commerciale (hébergement, lingerie, plonge, cuisine, ustensiles, machines, doseurs, services) |
| `crj_category` | texte | Catégorie de calcul : `CRJ Hebergement`, `CRJ Lingerie`, `CRJ Plonge`, `CRJ Cuisine`, `CRJ autres univers`, `Hors CRJ` |

## 🚧 `ref_occupancy` – taux d'occupation

Grain : un site × un mois. Nombre de lits occupés, fourni par le client dans un fichier dont le format change d'un trimestre à l'autre.

## ✅ `data/synthetic/ref/inactive_accounts.csv` – comptes inactifs

Comptes déclarés inactifs **après validation avec le métier** (équivalent du statut `_No CRJ` de l'outil d'origine).
Le compte est exclu en entier : ses ventes ne comptent pas dans le CRJ (voir D-012).

| Colonne | Type | Description |
|---|---|---|
| `account_id` | texte | Compte concerné |
| `reason` | texte | `pas de chiffre d'affaires` ou `commandes passées sur un autre compte` |
| `validated_by`, `validated_on` | texte, date | Qui a validé l'inactivité, et quand |

## ✅ `data/synthetic/ref/crj_target.csv` – cibles de CRJ

| Colonne | Type | Description |
|---|---|---|
| `crj_category` | texte | Catégorie CRJ |
| `linen_internalisation` | texte | Rempli pour la lingerie seulement : `INTERNE`, `PARTIEL`, `EXTERNE` |
| `crj_fixe`, `crj_variable` | décimal | Cible en € par lit et par jour, part fixe et part variable |
| `base_lits` | texte | `installés` ou `occupés` : base de lits du budget (voir D-014) |

## ✅ `CiblesSite` (requête Power Query) – cible applicable par site

Une ligne par site actif et par catégorie CRJ : `site_id`, `crj_category`, `linen_status`, `crj_fixe`, `crj_variable`, `base_lits`.
Pas de ligne lingerie pour un site sans statut de linge (voir D-015).

## 🚧 `dim_date` – calendrier

Une ligne par jour : année, trimestre, mois, nombre de jours du mois, indicateur de période d'analyse.
