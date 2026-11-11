// Occupation
// Empile les fichiers trimestriels d'occupation, toutes mises en page confondues.
// Les mois sans valeur restent à null : ils sont traités (et signalés) à l'étape suivante, pas masqués ici.
let
    Fichiers = Folder.Files(RacineProjet & "\data\synthetic\occupancy"),
    Classeurs = Table.SelectRows(Fichiers, each Text.Lower([Extension]) = ".xlsx" and not Text.StartsWith([Name], "~$")),
    Lus      = Table.AddColumn(Classeurs, "Donnees", each fnLireOccupation([Content], [Name])),
    Empiles  = Table.Combine(Lus[Donnees]),
    Types    = Table.TransformColumnTypes(Empiles, {
        {"account_id", type text}, {"month", type date}, {"installed_beds", Int64.Type},
        {"occupied_beds", type number}, {"layout", type text}, {"source_file", type text}})
in
    Types
