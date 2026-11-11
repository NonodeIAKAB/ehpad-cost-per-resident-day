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

Contrôle attendu avec la graine 42 : `260,402 sales lines, 435 SKUs, 36 months`.

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
2. Créer les requêtes **dans cet ordre** (une requête qui en appelle une autre doit être créée après elle) : `fnLireExportVentes`, `fnLireOccupation`, `fnLireReference`, puis `Ventes`, `Occupation`, `Produits`, `Comptes`, `ComptesExclus`, `CiblesCRJ`, `Sites`.
3. Pour chacune : Nouvelle source → Autres sources → Requête vide → Éditeur avancé → coller **tout** le contenu du fichier `.pq` → renommer la requête exactement comme le fichier, sans `.pq`. Un fichier = une requête.
4. Les fonctions (`fn…`) se chargent en « connexion uniquement ».

Pourquoi un paramètre et pas une cellule Excel : lire une cellule (`Excel.CurrentWorkbook`) est une source de données. La combiner avec `Folder.Files` déclenche l'erreur `Formula.Firewall` (pare-feu de confidentialité). Un paramètre est une simple valeur : pas de combinaison de sources, pas de pare-feu, et aucun réglage de confidentialité à désactiver.

Contrôles attendus après actualisation (graine 42) :

| Requête | Lignes | Autre contrôle |
|---|---|---|
| Ventes | 260 402 | Somme de `net_invoice_value` = 13 151 687,36 € |
| Occupation | 10 800 | 36 valeurs `occupied_beds` vides ; colonne `layout` : A, B et C présents |
| Produits | 435 | |
| Comptes | 311 | |
| ComptesExclus | 12 | |
| CiblesCRJ | 7 | |
| Sites | 300 | |
