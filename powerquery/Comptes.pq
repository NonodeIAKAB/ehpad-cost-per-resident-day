// Comptes : comptes de facturation, site rattaché, segment, statut d'internalisation du linge
fnLireReference("dim_account.csv", {
    {"account_id", type text}, {"site_id", type text}, {"segment", type text}, {"linen_internalisation", type text}})
