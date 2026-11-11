# Journal des décisions

Chaque choix structurant, avec ce qui a été écarté et pourquoi.
Format : contexte → décision → alternatives écartées → conséquences.
Statut : ✅ acté · ⚠️ hypothèse ouverte, à confirmer.

---

## D-001 ✅ Source : FINESS+ converti par `referentiels-sante`

**Contexte.** Il faut des sites réalistes (capacité, localisation) sans utiliser de données client.
Le flux officiel FINESS+ de l'ANS est un JSON d'environ 750 Mo décompressés ; l'ancienne extraction CSV n'est plus mise à jour depuis juillet 2026.

**Décision.** Utiliser l'archive mensuelle `finess.zip` publiée par l'outil libre `referentiels-sante` (Licence Ouverte 2.0), instantané ANS du 1er novembre 2026.

**Écarté.** Parser le JSON officiel : utile pour un projet d'ingénierie de données, hors sujet ici et sans valeur ajoutée pour l'analyse CRJ.

**Conséquences.** Dépendance à un outil communautaire : la date de l'instantané et la mention de la source sont versionnées dans `MENTION-SOURCE.txt`.

## D-002 ✅ Tout lire en texte, échouer si une colonne manque

**Contexte.** Les numéros FINESS et les codes département commencent parfois par 0 (`010001234`, `01`).
L'outil Excel d'origine cassait en silence quand une colonne source était renommée.

**Décision.** Lecture avec `dtype=str` ; conversion numérique explicite colonne par colonne.
Contrôle des en-têtes avant lecture : une colonne absente arrête le traitement avec un message clair.

**Écarté.** Laisser pandas deviner les types (perte des zéros), ou remplacer les erreurs par des valeurs vides (anomalies masquées).

## D-003 ✅ Dénominateur du CRJ : lits d'hébergement complet en service

**Contexte.** La première version sommait toutes les capacités déclarées d'un site.
Contrôle sur les vraies données : moyenne de 81,9 lits, maximum 235. En cause :
- l'activité 177 « Section Cure Médicale (dont) » est un sous-ensemble de l'hébergement permanent (double compte) ;
- l'accueil de jour et les PASA (961) comptent des places, pas des lits ;
- des activités inactives étaient incluses.

**Décision.** Ne compter que `niveau = exercee`, `statut = 1` (active et mise en œuvre), `mode_fonctionnement = 11` (hébergement complet), activités 924 (permanent) et 657 (temporaire).
Résultat : moyenne 76,2 lits, maximum 156. 58 EHPAD sans hébergement en service sont rejetés et tracés dans le rapport qualité.

**Écarté.** Garder la somme brute (biais d'environ +7 % sur le dénominateur, donc un CRJ sous-estimé d'autant).

## D-004 ⚠️ Unités d'hébergement renforcées (UHR, activité 962) exclues

**Contexte.** On ne sait pas encore si FINESS compte les lits d'UHR à l'intérieur de l'hébergement permanent (924) ou à côté.

**Décision provisoire.** Les exclure : un double compte fausserait le CRJ, un oubli de quelques lits le fausse moins.

**À faire.** Comparer, sur les sites qui ont une UHR, la capacité 924 avec la capacité autorisée totale ; ou trouver la règle dans la documentation de l'ANS.

## D-005 ✅ Panel : 300 EHPAD privés lucratifs, plafond de 2 % par entité juridique

**Contexte.** Le cas réel est un groupe privé national d'environ 300 sites.

**Décision.** Tirage aléatoire (graine 42) de 300 EHPAD privés lucratifs actifs, au plus 6 sites par entité juridique.

**Pourquoi le plafond.** Sans lui, le panel pourrait reproduire le parc d'un vrai groupe, et donc suggérer des ventes fictives chez un opérateur identifiable.

## D-006 ✅ Pseudonymisation de la dimension site

**Contexte.** Les ventes associées aux sites seront synthétiques. Les rattacher à de vrais établissements nommés reviendrait à publier de fausses données commerciales sur des entreprises réelles.

**Décision.** Retirer le nom et le numéro FINESS, remplacer par `site_id`, arrondir la position à 0,01° (environ 1 km).
On garde les attributs réels utiles à l'analyse : capacité, département, secteur, année d'ouverture.

**Écarté.** Garder le FINESS pour la traçabilité : la reproductibilité est assurée autrement (script, graine, date de l'instantané).

## D-007 ✅ Positions calculées depuis x/y : conservées

**Contexte.** Dans l'instantané de novembre 2026, 1 862 EHPAD actifs n'ont de position qu'en coordonnées projetées (x/y) ; l'outil de conversion en déduit la latitude et la longitude.

**Décision.** Les conserver (l'outil documente une précision au centimètre là où les deux existent), mais les signaler dans le rapport qualité (`position_computed_from_xy`).

## D-008 ⚠️ Données de ventes synthétiques, paramètres inventés

**Contexte.** Les données de la mission sont confidentielles.

**Décision.** Le générateur reproduit la **structure** observée (grain, familles, catégories CRJ, part des lignes hors CRJ, avoirs, défauts de saisie), jamais les **valeurs** : volumes, prix, cibles de CRJ et clés de répartition fixe/variable sont inventés.

**À confirmer.** Formule du CRJ : chiffre d'affaires de la catégorie ÷ (lits occupés × jours de la période).

## D-009 ✅ Générateur calé sur les cibles, 36 mois d'historique

**Contexte.** Des taux de consommation inventés donnent des CRJ arbitraires (premier essai : médiane hébergement à 0,165 € pour une cible à 0,110 €), donc une analyse sans intérêt.

**Décision.** Après génération, les montants de chaque catégorie sont remis à l'échelle pour que le site médian soit proche de sa cible (entre 0 et 6 % au-dessus). La dispersion entre sites vient d'un facteur d'efficacité propre à chaque site : c'est ce que l'analyse du CRJ doit faire ressortir.
Période : janvier 2023 à décembre 2025 (36 mois), pour servir aussi au futur projet de prévision.

**Résultat (graine 42).** 260 402 lignes, 435 articles ; CRJ total médian de 0,37 €/résident/jour, de 0,26 € à 0,56 € entre le 1er et le 9e décile des sites.

## D-010 ✅ Anomalies injectées et « vérité terrain » séparée

**Contexte.** Un pipeline de nettoyage ne se juge que sur des défauts connus à l'avance.

**Décision.** Le générateur injecte les défauts rencontrés pendant la mission (articles non catégorisés, comptes exclus encore facturés, avoirs, doublons exacts, statut d'internalisation du linge manquant ou mal saisi, occupation manquante, fichier d'occupation dont la mise en page change chaque trimestre) et les liste dans `data/synthetic/_ground_truth/anomalies.csv`.
Les tests compareront ce que le pipeline détecte avec cette liste. Le pipeline lui-même ne lit jamais `_ground_truth/`.
