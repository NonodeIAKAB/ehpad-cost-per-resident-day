// fnLireReference
// Lit un fichier de référence CSV (séparateur ",", point décimal) du dossier data\synthetic\ref.
// Les cellules vides deviennent null, pour que "non renseigné" soit détectable et non confondu avec "".
(nomFichier as text, types as list) as table =>
let
    Contenu  = File.Contents(RacineProjet & "\data\synthetic\ref\" & nomFichier),
    Brut     = Csv.Document(Contenu, [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Entetes  = Table.PromoteHeaders(Brut, [PromoteAllScalars = true]),
    Attendues = List.Transform(types, each _{0}),
    Manquantes = List.Difference(Attendues, Table.ColumnNames(Entetes)),
    Controle = if List.IsEmpty(Manquantes) then Entetes
               else error Error.Record("Schéma invalide", nomFichier & " : colonnes manquantes : " & Text.Combine(Manquantes, ", ")),
    Nulls    = Table.ReplaceValue(Controle, "", null, Replacer.ReplaceValue, Attendues),
    Types    = Table.TransformColumnTypes(Nulls, types, "en-US")
in
    Types
