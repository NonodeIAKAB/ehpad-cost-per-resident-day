// CiblesCRJ : cible en € par lit et par jour, part fixe et part variable, et base de lits du budget
//   base_lits = "installés" : budget = lits installés x (fixe + variable)   (hébergement, plonge, cuisine, autres)
//   base_lits = "occupés"   : budget = lits occupés x variable              (lingerie, selon le statut du linge)
fnLireReference("crj_target.csv", {
    {"crj_category", type text}, {"linen_internalisation", type text},
    {"crj_fixe", type number}, {"crj_variable", type number}, {"base_lits", type text}})
