# Mode opératoire

Toutes les commandes du projet, dans l'ordre, avec le rôle de chaque option.
Les commandes se lancent dans un terminal ouvert **à la racine du dépôt** (PowerShell sous Windows).

## 1. Préparer l'environnement Python (une seule fois)

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

| Élément | Rôle |
|---|---|
| `python -m venv .venv` | Crée un environnement Python isolé dans le dossier `.venv`. `-m venv` lance le module standard de création d'environnement. Les bibliothèques du projet n'interfèrent pas avec celles du poste |
| `.venv\Scripts\Activate.ps1` | Active cet environnement : `python` et `pip` pointent désormais vers `.venv`. Le préfixe `(.venv)` apparaît dans le terminal |
| `pip install -r requirements.txt` | Installe les bibliothèques listées dans le fichier. `-r` = « lire la liste dans ce fichier » |
| `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` | Seulement si PowerShell bloque l'activation. Autorise les scripts locaux pour l'utilisateur courant, sans droits administrateur |

## 2. Construire la dimension des sites (FINESS)

Prérequis : `finess.zip` téléchargé depuis
<https://github.com/Irreductix/referentiels-sante/releases/download/donnees-du-mois/finess.zip>
et décompressé dans `data/raw/finess/` (dossier ignoré par Git).

```powershell
python src/extract_finess_ehpad.py --etablissements data/raw/finess/etablissements.csv --activites data/raw/finess/activites.csv --out data/reference --n 300 --seed 42
```

| Option | Rôle | Valeur par défaut |
|---|---|---|
| `--etablissements` | Chemin du fichier FINESS des établissements. Obligatoire | — |
| `--activites` | Chemin du fichier des activités, d'où vient le nombre de lits. Sans lui, aucun site n'a de capacité et tous sont rejetés | — |
| `--out` | Dossier où écrire `dim_site.csv`, le rapport qualité et le résumé | — |
| `--n` | Nombre de sites du panel | 300 |
| `--seed` | « Graine » du tirage aléatoire. Même graine + mêmes données = exactement le même panel, à chaque exécution et sur chaque poste. Changer la graine donne un autre panel, aussi valable. 42 est une convention, sans signification | 42 |
| `--secteur` | Secteur conservé. `--secteur ""` garde tous les secteurs | `privé lucratif` |

## 3. Générer les ventes synthétiques

```powershell
python src/generate_synthetic_sales.py --seed 42
```

| Option | Rôle | Valeur par défaut |
|---|---|---|
| `--sites` | Dimension des sites produite à l'étape 2 | `data/reference/dim_site.csv` |
| `--out` | Dossier de sortie | `data/synthetic` |
| `--seed` | Même rôle qu'à l'étape 2 : rend les ventes, les anomalies et les fichiers d'occupation reproductibles | 42 |

Contrôle attendu avec la graine 42 : `253,474 sales lines, 435 SKUs, 36 months, 12,674,264 EUR`.

## 4. Git

| Commande | Rôle |
|---|---|
| `git init` | Transforme le dossier en dépôt Git (une seule fois) |
| `git add <chemins>` | Sélectionne les fichiers à inclure dans le prochain commit |
| `git status` | Montre ce qui est sélectionné. À lancer **avant chaque commit** : `data/raw/` ne doit jamais apparaître |
| `git commit -m "message"` | Enregistre la sélection avec un message. `-m` = message en ligne de commande |
| `git rm -r --cached <dossier>` | Retire un dossier du suivi Git sans le supprimer du disque. `-r` = récursif, `--cached` = ne toucher qu'à l'index Git |
| `git rebase -i --root` | Réécrit l'historique depuis le premier commit, par exemple pour renommer des messages (`reword`). `-i` = interactif. À faire **avant** d'avoir poussé |

### Convention des messages de commit

Format Conventional Commits, en français : `type(portée): description à l'infinitif ou au nom`.

| Type | Usage |
|---|---|
| `feat` | Nouvelle fonctionnalité |
| `fix` | Correction d'un défaut |
| `docs` | Documentation seule |
| `refactor` | Réorganisation du code sans changement de résultat |
| `test` | Ajout ou modification de tests |
| `chore` | Entretien (dépendances, `.gitignore`…) |

Portées utilisées : `data` (extraction, génération), `pq` (Power Query), `model` (modèle et DAX), `docs`.

## 5. Power Query (Excel)

1. Créer le paramètre : Accueil → Gérer les paramètres → Nouveau paramètre. Nom `RacineProjet`, type Texte, valeur actuelle = chemin de la racine du dépôt, sans `\` final. C'est le seul endroit où un chemin apparaît.
2. Créer les requêtes **dans cet ordre** (une requête qui en appelle une autre doit être créée après elle) : `fnLireExportVentes`, `fnLireOccupation`, `fnLireReference`, puis `Ventes`, `Occupation`, `Produits`, `Comptes`, `ComptesInactifs`, `CiblesCRJ`, `Sites`.
3. Pour chacune : Nouvelle source → Autres sources → Requête vide → Éditeur avancé → coller **tout** le contenu du fichier `.pq` → renommer la requête exactement comme le fichier, sans `.pq`. Un fichier = une requête.
4. Les fonctions (`fn…`) se chargent en « connexion uniquement ».

Pourquoi un paramètre et pas une cellule Excel : lire une cellule (`Excel.CurrentWorkbook`) est une source de données. La combiner avec `Folder.Files` déclenche l'erreur `Formula.Firewall` (pare-feu de confidentialité). Un paramètre est une simple valeur : pas de combinaison de sources, pas de pare-feu, et aucun réglage de confidentialité à désactiver.

Contrôles attendus après actualisation (graine 42) :

| Requête | Lignes | Autre contrôle |
|---|---|---|
| Ventes | 253 474 | Somme de `net_invoice_value` = 12 674 264,25 € |
| Occupation | 10 800 | 36 valeurs `occupied_beds` vides ; colonne `layout` : A, B et C présents |
| Produits | 435 | |
| Comptes | 323 | |
| ComptesInactifs | 27 | |
| CiblesCRJ | 7 | |
| Sites | 300 | |

## 6. Couche de nettoyage et modèle (Power Query → Power Pivot)

Les requêtes de la section 5 forment la couche **staging** : elles lisent les sources telles quelles.
Les requêtes ci-dessous forment la couche **modèle** : elles nettoient, qualifient et alimentent Power Pivot.

Ordre de création : `DimCompte`, `DimProduit`, `DimSite`, `DimCategorieCRJ`, `FaitVentes`, `FaitOccupation`, `DimCalendrier`, `CiblesSite`, `Exceptions`.

Destination de chargement (Fermer et charger dans… ) :

| Requêtes | Destination |
|---|---|
| `RacineProjet`, `fn…`, `Ventes`, `Occupation`, `Produits`, `Comptes`, `ComptesInactifs`, `Sites`, `CiblesCRJ` | Connexion uniquement |
| `DimCompte`, `DimProduit`, `DimSite`, `DimCategorieCRJ`, `DimCalendrier`, `FaitVentes`, `FaitOccupation`, `CiblesSite` | Connexion uniquement **+ Ajouter au modèle de données** |
| `Exceptions` | Tableau dans un onglet `Exceptions` (liste de travail visible) |

Contrôles attendus (graine 42) :

| Requête | Contrôle |
|---|---|
| FaitVentes | 253 474 lignes (aucune supprimée) ; somme = 12 674 264,25 € ; 195 lignes `is_inactive_account` = VRAI (10 269,22 €, catégorie « Hors CRJ - compte inactif ») ; 504 lignes `is_duplicate` = VRAI (252 paires) ; 1 009 avoirs |
| FaitOccupation | 10 800 lignes ; 36 `is_imputed` = VRAI ; aucune `occupied_beds` vide |
| DimCalendrier | 1 096 jours (2023 à 2025) |
| DimCompte | 323 comptes ; 9 sites avec `linen_status` vide |
| Exceptions | 338 lignes : 14 articles sans catégorie, 9 statuts linge, 252 doublons, 23 comptes inactifs avec chiffre d'affaires, 4 sites sans compte actif, 36 occupations manquantes, 0 article ou compte inconnu |

## 7. Modèle de données (Power Pivot)

Power Pivot → Gérer → Vue de diagramme. Créer les relations en faisant glisser la colonne de la table de faits sur la colonne de la dimension :

| De (côté plusieurs) | Vers (côté un) |
|---|---|
| `FaitVentes[month]` | `DimCalendrier[date]` |
| `FaitVentes[site_id]` | `DimSite[site_id]` |
| `FaitVentes[sku]` | `DimProduit[sku]` |
| `FaitVentes[account_id]` | `DimCompte[account_id]` |
| `FaitVentes[crj_scope]` | `DimCategorieCRJ[crj_category]` |
| `FaitOccupation[month]` | `DimCalendrier[date]` |
| `FaitOccupation[site_id]` | `DimSite[site_id]` |
| `CiblesSite[site_id]` | `DimSite[site_id]` |
| `CiblesSite[crj_category]` | `DimCategorieCRJ[crj_category]` |

Puis : sélectionner `DimCalendrier` → Conception → Marquer comme table de dates → colonne `date`.
Mesures : copier celles de `model/mesures.dax`, dans la table `FaitVentes`.

Contrôles attendus (tableau croisé : années en lignes) :

| Année | CA total | CA CRJ | Résidents-jours | Taux d'occupation | CRJ réel | CRJ capacité théorique |
|---|---|---|---|---|---|---|
| 2023 | 4 071 645,04 | 2 740 742,43 | 7 588 805 | 92,3 % | 0,3612 | 0,3334 |
| 2024 | 4 239 386,01 | 2 867 878,53 | 7 606 575 | 92,3 % | 0,3770 | 0,3479 |
| 2025 | 4 363 233,20 | 2 947 948,09 | 7 587 262 | 92,3 % | 0,3885 | 0,3586 |

`Nb sites CRJ` = 296 ; CRJ réel du T3 2025 = 0,3862.

Contrôles du budget (années en lignes) :

| Année | Budget CRJ | CA CRJ comparable | Écart budget € | Écart budget % | CRJ cible | CRJ réel comparable | Nb sites au-dessus du budget |
|---|---|---|---|---|---|---|---|
| 2023 | 2 750 520,76 | 2 719 478,37 | −31 042,39 | −1,13 % | 0,3624 | 0,3584 | 125 |
| 2024 | 2 757 624,80 | 2 847 223,72 | 89 598,92 | 3,25 % | 0,3625 | 0,3743 | 143 |
| 2025 | 2 750 264,86 | 2 922 839,90 | 172 575,04 | 6,27 % | 0,3625 | 0,3852 | 168 |

`CiblesSite` : 1 471 lignes (296 sites actifs × 4 catégories communes + 287 cibles lingerie ; 9 sites sans statut de linge n'ont pas de ligne lingerie).
