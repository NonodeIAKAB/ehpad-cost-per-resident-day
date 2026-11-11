// Sites : dimension des 300 EHPAD issue de FINESS (data\reference, pas data\synthetic\ref)
let
    Contenu = File.Contents(RacineProjet & "\data\reference\dim_site.csv"),
    Brut    = Csv.Document(Contenu, [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Entetes = Table.PromoteHeaders(Brut, [PromoteAllScalars = true]),
    Types   = Table.TransformColumnTypes(Entetes, {
        {"site_id", type text}, {"secteur", type text}, {"departement", type text}, {"departement_libelle", type text},
        {"nb_lits_installes", Int64.Type}, {"annee_ouverture", Int64.Type},
        {"latitude", type number}, {"longitude", type number}}, "en-US")
in
    Types
