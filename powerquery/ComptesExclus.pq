// ComptesExclus : comptes que le métier demande de sortir du calcul du CRJ
fnLireReference("excluded_accounts.csv", {
    {"account_id", type text}, {"reason", type text}, {"since", type date}})
