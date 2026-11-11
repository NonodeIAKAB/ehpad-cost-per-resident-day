// Ventes
// Empile tous les exports mensuels déposés dans data\synthetic\sales.
// Ajouter un mois = déposer un fichier, sans toucher à la requête.
let
    Fichiers   = Folder.Files(RacineProjet & "\data\synthetic\sales"),
    Exports    = Table.SelectRows(Fichiers, each Text.Lower([Extension]) = ".csv" and Text.StartsWith([Name], "sales_")),
    Lus        = Table.AddColumn(Exports, "Donnees", each fnLireExportVentes([Content], [Name])),
    Empiles    = Table.Combine(Lus[Donnees]),
    Types      = Table.TransformColumnTypes(Empiles, {
        {"account_id", type text}, {"sku", type text}, {"month", type date},
        {"quantity", type number}, {"net_invoice_value", Currency.Type}, {"source_file", type text}})
in
    Types
