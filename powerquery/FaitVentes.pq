// FaitVentes : table de faits des ventes, nettoyée et qualifiée
// Rien n'est supprimé : chaque ligne porte des indicateurs (compte inactif, avoir, doublon...)
// et une catégorie de calcul crj_scope. Le total de cette table = le total des exports.
let
    Cles = {"account_id", "sku", "month", "quantity", "net_invoice_value"},

    // Petites tables mises en mémoire une fois : sinon Power Query peut les relire à chaque jointure
    Comptes_ = Table.Buffer(DimCompte),
    Produits_ = Table.Buffer(DimProduit),
    Inactifs_ = Table.Buffer(ComptesInactifs),

    // Site du compte
    J1 = Table.NestedJoin(Ventes, {"account_id"}, Comptes_, {"account_id"}, "c", JoinKind.LeftOuter),
    E1 = Table.ExpandTableColumn(J1, "c", {"site_id"}),

    // Catégorie de l'article ; sku_ref permet de distinguer "article inconnu" de "article sans catégorie"
    J2 = Table.NestedJoin(E1, {"sku"}, Produits_, {"sku"}, "p", JoinKind.LeftOuter),
    E2 = Table.ExpandTableColumn(J2, "p", {"sku", "crj_category"}, {"sku_ref", "crj_category"}),

    // Compte déclaré inactif (validé avec le métier) : ses ventes sont exclues du CRJ.
    // Elles restent dans la table, catégorie "Hors CRJ - compte inactif", pour que le total rapproche.
    J3 = Table.NestedJoin(E2, {"account_id"}, Inactifs_, {"account_id"}, "x", JoinKind.LeftOuter),
    E3 = Table.ExpandTableColumn(J3, "x", {"reason"}, {"inactive_reason"}),
    Inactif = Table.AddColumn(E3, "is_inactive_account", each [inactive_reason] <> null, type logical),

    // Catégorie réellement utilisée par le calcul
    Perimetre = Table.AddColumn(Inactif, "crj_scope", each
        if [is_inactive_account] then "Hors CRJ - compte inactif"
        else if [sku_ref] = null then "Article inconnu"
        else [crj_category], type text),

    Avoir = Table.AddColumn(Perimetre, "is_credit_note", each [net_invoice_value] < 0, type logical),

    // Doublons exacts : signalés, pas supprimés (deux livraisons identiques le même mois sont possibles)
    // Table.Buffer : "Avoir" sert deux fois (comptage puis jointure). Sans mise en mémoire, Power Query
    // relirait les 36 fichiers et refairait toutes les jointures une seconde fois.
    Base = Table.Buffer(Avoir),
    Groupes = Table.Group(Base, Cles, {{"duplicate_count", each Table.RowCount(_), Int64.Type}}),
    J4 = Table.NestedJoin(Base, Cles, Groupes, Cles, "g", JoinKind.LeftOuter),
    E4 = Table.ExpandTableColumn(J4, "g", {"duplicate_count"}),
    Doublon = Table.AddColumn(E4, "is_duplicate", each [duplicate_count] > 1, type logical),

    Final = Table.SelectColumns(Doublon, {
        "account_id", "site_id", "sku", "month", "quantity", "net_invoice_value",
        "crj_category", "crj_scope", "is_inactive_account", "is_credit_note", "is_duplicate", "source_file"}),
    Types = Table.TransformColumnTypes(Final, {
        {"site_id", type text}, {"crj_category", type text}, {"net_invoice_value", Currency.Type}})
in
    Types
