// DimCategorieCRJ : les catégories de calcul, avec leur ordre d'affichage et leur appartenance au CRJ
// Liste fermée : toute valeur de FaitVentes[crj_scope] doit y figurer (contrôlé dans Exceptions).
#table(
    type table [crj_category = text, ordre = Int64.Type, dans_crj = logical, univers = text],
    {
        {"CRJ Hebergement",           1, true,  "CRJ"},
        {"CRJ Lingerie",              2, true,  "CRJ"},
        {"CRJ Plonge",                3, true,  "CRJ"},
        {"CRJ Cuisine",               4, true,  "CRJ"},
        {"CRJ autres univers",        5, true,  "CRJ"},
        {"Hors CRJ",                  6, false, "Hors CRJ"},
        {"Hors CRJ - compte inactif", 7, false, "Hors CRJ"},
        {"Non catégorisé",            8, false, "À traiter"},
        {"Article inconnu",           9, false, "À traiter"}
    })
