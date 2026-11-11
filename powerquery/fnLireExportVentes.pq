// fnLireExportVentes
// Lit UN export mensuel de ventes (séparateur ";", virgule décimale, mois en toutes lettres).
// Échoue avec un message explicite si une colonne attendue manque, au lieu de produire des vides.
(contenu as binary, nomFichier as text) as table =>
let
    Brut      = Csv.Document(contenu, [Delimiter = ";", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Entetes   = Table.PromoteHeaders(Brut, [PromoteAllScalars = true]),
    // Retire l'éventuel BOM UTF-8 et les espaces parasites des en-têtes
    Propres   = Table.TransformColumnNames(Entetes, each Text.Trim(Text.Replace(_, Character.FromNumber(65279), ""))),

    Attendues = {"CODE CLIENT", "SKU", "ANNEE", "MOIS", "Volume", "Net Invoice Value"},
    Manquantes = List.Difference(Attendues, Table.ColumnNames(Propres)),
    Controle  = if List.IsEmpty(Manquantes) then Propres
                else error Error.Record("Schéma invalide", nomFichier & " : colonnes manquantes : " & Text.Combine(Manquantes, ", ")),

    // "fr-FR" : la virgule est lue comme séparateur décimal
    Types = Table.TransformColumnTypes(Controle, {
        {"CODE CLIENT", type text}, {"SKU", type text}, {"ANNEE", Int64.Type}, {"MOIS", type text},
        {"Volume", type number}, {"Net Invoice Value", type number}}, "fr-FR"),

    MoisFr = {"janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"},
    AvecDate = Table.AddColumn(Types, "month", each
        let i = List.PositionOf(MoisFr, Text.Lower(Text.Trim([MOIS])))
        in  if i < 0 then error Error.Record("Mois inconnu", nomFichier & " : '" & [MOIS] & "'") else #date([ANNEE], i + 1, 1),
        type date),

    Renommees = Table.RenameColumns(AvecDate, {
        {"CODE CLIENT", "account_id"}, {"SKU", "sku"}, {"Volume", "quantity"}, {"Net Invoice Value", "net_invoice_value"}}),
    AvecSource = Table.AddColumn(Renommees, "source_file", each nomFichier, type text),
    Resultat  = Table.SelectColumns(AvecSource, {"account_id", "sku", "month", "quantity", "net_invoice_value", "source_file"})
in
    Resultat
