// DimProduit : référentiel articles. Un article sans catégorie CRJ n'est pas supprimé :
// il est classé "Non catégorisé", reste hors du CRJ et remonte dans Exceptions pour le KAM.
let
    Source = Produits,
    Categorie = Table.AddColumn(Source, "crj_category_model", each
        if [crj_category] = null then "Non catégorisé" else [crj_category], type text),
    Final = Table.RenameColumns(Table.RemoveColumns(Categorie, {"crj_category"}), {{"crj_category_model", "crj_category"}})
in
    Final
