// DimCalendrier : une ligne par jour, années complètes couvrant la période des données
let
    Debut = Date.StartOfYear(List.Min(Occupation[month])),
    Fin   = Date.EndOfYear(List.Max(Occupation[month])),
    Dates = List.Dates(Debut, Duration.Days(Fin - Debut) + 1, #duration(1, 0, 0, 0)),
    Table0 = Table.FromList(Dates, Splitter.SplitByNothing(), {"date"}),
    Typee  = Table.TransformColumnTypes(Table0, {{"date", type date}}),
    Annee     = Table.AddColumn(Typee, "annee", each Date.Year([date]), Int64.Type),
    Trimestre = Table.AddColumn(Annee, "trimestre", each "T" & Text.From(Date.QuarterOfYear([date])), type text),
    NumMois   = Table.AddColumn(Trimestre, "num_mois", each Date.Month([date]), Int64.Type),
    Mois      = Table.AddColumn(NumMois, "mois", each Date.MonthName([date], "fr-FR"), type text),
    AnneeMois = Table.AddColumn(Mois, "annee_mois", each Text.From(Date.Year([date])) & "-" & Text.PadStart(Text.From(Date.Month([date])), 2, "0"), type text),
    DebutMois = Table.AddColumn(AnneeMois, "debut_mois", each Date.StartOfMonth([date]), type date),
    Jours     = Table.AddColumn(DebutMois, "jours_dans_mois", each Date.DaysInMonth([date]), Int64.Type)
in
    Jours
