// fnLireOccupation
// Lit UN fichier trimestriel d'occupation, quelle que soit sa mise en page :
//   A. tableau en lignes      : Code client | Mois (AAAA-MM) | Nb lits total | Nb lits occupés
//   B. un mois par colonne    : CODE CLIENT | NB LITS | Occupés MM/AAAA | ...
//   C. bloc de titre au-dessus : Code client | Période (JJ/MM/AAAA) | Lits installés | Taux occupation
// La ligne d'en-tête est cherchée (première cellule = "code client", casse ignorée) au lieu
// d'un Table.Skip(n) figé. Une mise en page inconnue arrête l'actualisation avec un message clair.
(contenu as binary, nomFichier as text) as table =>
let
    Feuille   = Excel.Workbook(contenu, null, true){0}[Data],
    Numerotee = Table.AddIndexColumn(Feuille, "__ligne", 0, 1),
    Candidates = Table.SelectRows(Numerotee, each
        Text.Lower(Text.Trim(if [Column1] = null then "" else Text.From([Column1]))) = "code client"),
    LigneEntete = if Table.IsEmpty(Candidates)
        then error Error.Record("En-tête introuvable", nomFichier & " : aucune ligne ne commence par 'Code client'")
        else Candidates{0}[__ligne],
    Entetes   = Table.PromoteHeaders(Table.Skip(Feuille, LigneEntete), [PromoteAllScalars = true]),
    Noms      = Table.ColumnNames(Entetes),
    NomsMin   = List.Transform(Noms, each Text.Lower(Text.Trim(_))),
    Normalise = Table.RenameColumns(Entetes, List.Zip({Noms, NomsMin})),
    SansVides = Table.SelectRows(Normalise, each [code client] <> null and Text.Trim(Text.From([code client])) <> ""),

    MiseEnPageA = () =>
        let
            T = Table.AddColumn(SansVides, "month", each
                    #date(Number.From(Text.Start(Text.From([mois]), 4)), Number.From(Text.End(Text.From([mois]), 2)), 1), type date),
            R = Table.RenameColumns(T, {{"nb lits total", "installed_beds"}, {"nb lits occupés", "occupied_beds"}})
        in  Table.AddColumn(R, "layout", each "A", type text),

    MiseEnPageB = () =>
        let
            ColonnesMois = List.Select(NomsMin, each Text.StartsWith(_, "occupés ")),
            // Table.Unpivot supprime les cellules vides : un mois manquant disparaîtrait sans trace.
            // On le marque (-1) avant de dépivoter, puis on le remet à null.
            Marques = Table.ReplaceValue(SansVides, null, -1, Replacer.ReplaceValue, ColonnesMois),
            Depivote = Table.Unpivot(Marques, ColonnesMois, "colonne", "occupied_beds"),
            Pivot = Table.ReplaceValue(Depivote, -1, null, Replacer.ReplaceValue, {"occupied_beds"}),
            T = Table.AddColumn(Pivot, "month", each
                    let mmaaaa = Text.AfterDelimiter([colonne], " ")
                    in  #date(Number.From(Text.End(mmaaaa, 4)), Number.From(Text.Start(mmaaaa, 2)), 1), type date),
            R = Table.RenameColumns(Table.RemoveColumns(T, {"colonne"}), {{"nb lits", "installed_beds"}})
        in  Table.AddColumn(R, "layout", each "B", type text),

    MiseEnPageC = () =>
        let
            T = Table.AddColumn(SansVides, "month", each
                    let p = Text.From([période])
                    in  #date(Number.From(Text.End(p, 4)), Number.From(Text.Middle(p, 3, 2)), 1), type date),
            O = Table.AddColumn(T, "occupied_beds", each
                    if [taux occupation] = null then null else [lits installés] * [taux occupation], type number),
            R = Table.RenameColumns(O, {{"lits installés", "installed_beds"}})
        in  Table.AddColumn(R, "layout", each "C", type text),

    Lu = if List.Contains(NomsMin, "nb lits occupés") then MiseEnPageA()
         else if List.Contains(NomsMin, "taux occupation") then MiseEnPageC()
         else if List.AnyTrue(List.Transform(NomsMin, each Text.StartsWith(_, "occupés "))) then MiseEnPageB()
         else error Error.Record("Mise en page inconnue", nomFichier & " : colonnes " & Text.Combine(Noms, ", ")),

    Renomme   = Table.RenameColumns(Lu, {{"code client", "account_id"}}),
    AvecSource = Table.AddColumn(Renomme, "source_file", each nomFichier, type text),
    Resultat  = Table.SelectColumns(AvecSource, {"account_id", "month", "installed_beds", "occupied_beds", "layout", "source_file"})
in
    Resultat
