// FaitOccupation : lits installés et occupés par site et par mois, base du dénominateur du CRJ
// Un mois sans valeur est remplacé par la moyenne du site sur le trimestre, et marqué is_imputed.
// resident_days = lits occupés x jours du mois ; installed_bed_days = lits installés x jours.
let
    J = Table.NestedJoin(Occupation, {"account_id"}, DimCompte, {"account_id"}, "c", JoinKind.LeftOuter),
    E = Table.ExpandTableColumn(J, "c", {"site_id"}),
    AvecTrimestre = Table.AddColumn(E, "quarter_key", each Date.Year([month]) * 10 + Date.QuarterOfYear([month]), Int64.Type),

    Moyennes = Table.Group(AvecTrimestre, {"site_id", "quarter_key"},
        {{"avg_quarter", each List.Average(List.RemoveNulls([occupied_beds])), type number}}),
    J2 = Table.NestedJoin(AvecTrimestre, {"site_id", "quarter_key"}, Moyennes, {"site_id", "quarter_key"}, "m", JoinKind.LeftOuter),
    E2 = Table.ExpandTableColumn(J2, "m", {"avg_quarter"}),

    Impute  = Table.AddColumn(E2, "is_imputed", each [occupied_beds] = null, type logical),
    Valeur  = Table.AddColumn(Impute, "occupied_beds_final", each
        if [occupied_beds] = null then [avg_quarter] else [occupied_beds], type number),
    Jours   = Table.AddColumn(Valeur, "days", each Date.DaysInMonth([month]), Int64.Type),
    JR      = Table.AddColumn(Jours, "resident_days", each [occupied_beds_final] * [days], type number),
    JL      = Table.AddColumn(JR, "installed_bed_days", each [installed_beds] * [days], type number),

    Nettoye = Table.RenameColumns(Table.RemoveColumns(JL, {"occupied_beds", "avg_quarter", "quarter_key"}),
        {{"occupied_beds_final", "occupied_beds"}}),
    Final = Table.SelectColumns(Nettoye, {
        "site_id", "account_id", "month", "installed_beds", "occupied_beds", "is_imputed",
        "days", "resident_days", "installed_bed_days", "layout", "source_file"}),
    Types = Table.TransformColumnTypes(Final, {{"site_id", type text}})
in
    Types
