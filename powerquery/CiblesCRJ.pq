// CiblesCRJ : cible en € par résident et par jour, part fixe / part variable
fnLireReference("crj_target.csv", {
    {"crj_category", type text}, {"linen_internalisation", type text},
    {"target_eur_per_resident_day", type number}, {"share_fixed", type number}, {"share_variable", type number}})
