// CiblesSite : la cible applicable à chaque site actif, une ligne par site et par catégorie CRJ.
// Hors lingerie : même cible pour tous les sites.
// Lingerie : cible selon le statut d'internalisation du linge du site. Un site sans statut
// n'a PAS de ligne lingerie : sa lingerie sort de la comparaison avec la cible (règle métier).
let
    Cibles = Table.Buffer(CiblesCRJ),
    Colonnes = {"crj_category", "crj_fixe", "crj_variable", "base_lits"},

    // Statut du linge par site : premier statut renseigné parmi les comptes du site
    LingeParSite = Table.Group(DimCompte, {"site_id"},
        {{"linen_status", each List.First(List.RemoveNulls([linen_status])), type text}}),

    SitesActifs = Table.SelectColumns(Table.SelectRows(DimSite, each [a_compte_actif]), {"site_id"}),
    J = Table.NestedJoin(SitesActifs, {"site_id"}, LingeParSite, {"site_id"}, "l", JoinKind.LeftOuter),
    Sites_ = Table.ExpandTableColumn(J, "l", {"linen_status"}),

    // Cibles communes : chaque site reçoit chaque catégorie (produit cartésien)
    Communes = Table.SelectRows(Cibles, each [linen_internalisation] = null),
    Croise = Table.ExpandTableColumn(Table.AddColumn(Sites_, "c", each Communes), "c", Colonnes),

    // Cible lingerie : jointure interne sur le statut, donc aucune ligne si le statut est inconnu
    Linge = Table.SelectRows(Cibles, each [linen_internalisation] <> null),
    JL = Table.NestedJoin(Table.SelectRows(Sites_, each [linen_status] <> null), {"linen_status"},
                          Linge, {"linen_internalisation"}, "x", JoinKind.Inner),
    CibleLinge = Table.ExpandTableColumn(JL, "x", Colonnes),

    Tout = Table.Combine({Croise, CibleLinge}),
    Final = Table.SelectColumns(Tout, {"site_id", "crj_category", "linen_status", "crj_fixe", "crj_variable", "base_lits"}),
    Types = Table.TransformColumnTypes(Final, {
        {"site_id", type text}, {"crj_category", type text}, {"linen_status", type text},
        {"crj_fixe", type number}, {"crj_variable", type number}, {"base_lits", type text}})
in
    Types
