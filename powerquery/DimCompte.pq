// DimCompte : comptes de facturation avec le statut du linge normalisé
// La saisie client contient "INTERNE", "Interne", "partiel ", "INTERNE MUTUALISATION"...
// On ramène tout à INTERNE / PARTIEL / EXTERNE. Ce qui ne se ramène à rien reste null
// et remonte dans Exceptions : on ne devine pas un statut qui conditionne la cible lingerie.
let
    Source = Comptes,
    Normalise = Table.AddColumn(Source, "linen_status", each
        let u = if [linen_internalisation] = null then "" else Text.Upper(Text.Trim([linen_internalisation]))
        in  if Text.StartsWith(u, "INTERNE") then "INTERNE"
            else if Text.StartsWith(u, "PARTIEL") then "PARTIEL"
            else if Text.StartsWith(u, "EXTERNE") then "EXTERNE"
            else null,
        type text),
    Renomme = Table.RenameColumns(Normalise, {{"linen_internalisation", "linen_label_source"}})
in
    Renomme
