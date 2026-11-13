// Exceptions : tout ce que le pipeline a détecté, une ligne par anomalie, avec l'action attendue
// Remplace les ReplaceErrorValues de l'outil d'origine : une anomalie se voit, elle ne disparaît pas.
// À charger dans un onglet visible : c'est la liste de travail du KAM avant chaque publication.
let
    Formater = (t as table, controle as text, gravite as text, action as text) as table =>
        Table.SelectColumns(
            Table.AddColumn(Table.AddColumn(Table.AddColumn(t,
                "controle", each controle, type text),
                "gravite", each gravite, type text),
                "action", each action, type text),
            {"controle", "gravite", "cle", "nb_lignes", "montant", "action"}),

    ParCle = (t as table, colonne as text) as table =>
        Table.RenameColumns(
            Table.Group(t, {colonne}, {
                {"nb_lignes", each Table.RowCount(_), Int64.Type},
                {"montant", each List.Sum([net_invoice_value]), type number}}),
            {{colonne, "cle"}}),

    // FaitVentes est utilisée 6 fois ci-dessous : mise en mémoire une seule fois.
    // Sans Table.Buffer, Power Query la recalculerait entièrement à chaque usage (36 fichiers + jointures, x6).
    V = Table.Buffer(FaitVentes),
    O = Table.Buffer(FaitOccupation),

    SkuNonCategorise = Formater(ParCle(Table.SelectRows(V, each [crj_category] = "Non catégorisé"), "sku"),
        "Article sans catégorie CRJ", "À traiter", "Demander la catégorie au KAM ; l'article reste hors CRJ en attendant"),

    SkuInconnu = Formater(ParCle(Table.SelectRows(V, each [crj_scope] = "Article inconnu"), "sku"),
        "Article absent du référentiel", "Bloquant", "Ajouter l'article au référentiel produits"),

    CompteInconnu = Formater(ParCle(Table.SelectRows(V, each [site_id] = null), "account_id"),
        "Compte absent du référentiel", "Bloquant", "Rattacher le compte à un site"),

    CompteInactifAvecVentes = Formater(ParCle(Table.SelectRows(V, each [is_inactive_account]), "account_id"),
        "Compte inactif avec chiffre d'affaires", "À vérifier", "Ventes exclues du CRJ ; confirmer avec le métier que le compte est bien inactif"),

    SiteSansCompteActif =
        let
            AvecVentes = List.Distinct(Table.SelectRows(V, each not [is_inactive_account])[site_id]),
            t = Table.SelectRows(DimSite, each not List.Contains(AvecVentes, [site_id])),
            c = Table.RenameColumns(Table.SelectColumns(t, {"site_id"}), {{"site_id", "cle"}}),
            n = Table.AddColumn(Table.AddColumn(c, "nb_lignes", each 0, Int64.Type), "montant", each 0, type number)
        in  Formater(n, "Site sans vente sur un compte actif", "Information", "Pas de CRJ calculé pour ce site ; exclu des moyennes et classements"),

    Doublons =
        let
            t = Table.SelectRows(V, each [is_duplicate]),
            g = Table.Group(t, {"account_id", "sku", "month", "net_invoice_value"}, {{"nb_lignes", each Table.RowCount(_), Int64.Type}}),
            c = Table.AddColumn(g, "cle", each [account_id] & "|" & [sku] & "|" & Date.ToText([month], "yyyy-MM"), type text),
            m = Table.AddColumn(c, "montant", each [net_invoice_value] * ([nb_lignes] - 1), type number)
        in  Formater(m, "Ligne en double exact", "À vérifier", "Confirmer avec la facturation ; montant = excédent si doublon"),

    OccupationManquante =
        let
            t = Table.SelectRows(O, each [is_imputed]),
            c = Table.AddColumn(t, "cle", each [site_id] & "|" & Date.ToText([month], "yyyy-MM"), type text),
            n = Table.AddColumn(Table.AddColumn(c, "nb_lignes", each 1, Int64.Type), "montant", each null, type number)
        in  Formater(n, "Occupation manquante", "Information", "Valeur imputée (moyenne du trimestre) ; demander la donnée au client"),

    LingeNonRenseigne =
        let
            t = Table.Distinct(Table.SelectColumns(Table.SelectRows(DimCompte, each [linen_status] = null), {"site_id"})),
            c = Table.RenameColumns(t, {{"site_id", "cle"}}),
            n = Table.AddColumn(Table.AddColumn(c, "nb_lignes", each null, Int64.Type), "montant", each null, type number)
        in  Formater(n, "Statut du linge non renseigné", "À traiter", "Cible lingerie indéterminée ; obtenir le statut d'internalisation"),

    Tout = Table.Combine({SkuInconnu, CompteInconnu, SkuNonCategorise, LingeNonRenseigne, Doublons, CompteInactifAvecVentes, SiteSansCompteActif, OccupationManquante}),
    Types = Table.TransformColumnTypes(Tout, {{"cle", type text}, {"nb_lignes", Int64.Type}, {"montant", Currency.Type}})
in
    Types
