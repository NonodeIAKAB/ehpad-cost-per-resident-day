// DimSite : les 300 EHPAD issus de FINESS, avec un indicateur "a_compte_actif".
// Un site dont tous les comptes sont inactifs (validés avec le métier) n'a pas de CRJ :
// il sort du dénominateur et des moyennes.
let
    Inactifs     = List.Buffer(ComptesInactifs[account_id]),
    ComptesActifs = Table.SelectRows(Comptes, each not List.Contains(Inactifs, [account_id])),
    SitesActifs  = List.Buffer(List.Distinct(ComptesActifs[site_id])),
    AvecIndicateur = Table.AddColumn(Sites, "a_compte_actif", each List.Contains(SitesActifs, [site_id]), type logical)
in
    AvecIndicateur
