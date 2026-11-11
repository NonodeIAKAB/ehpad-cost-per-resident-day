"""Extract a reproducible panel of real EHPAD sites from the public FINESS+ files.

Builds the site dimension of the CRJ (cost per resident day) project:
real, public attributes (capacity, location, sector) for a sample of EHPAD,
with the names and FINESS numbers removed, because the sales facts attached
to them later are synthetic and must not be read as real commercial data.

Inputs (from the monthly finess.zip, Licence Ouverte 2.0, ANS):
    etablissements.csv  one row per establishment (';' separated, UTF-8 BOM)
    activites.csv       optional, gives the installed capacity

Outputs (in --out):
    dim_site.csv                published site dimension, pseudonymised
    data_quality_report.csv     every issue found, one row per site and check
    extraction_summary.json     source date, row counts, parameters

Usage:
    python src/extract_finess_ehpad.py \
        --etablissements data/raw/finess/etablissements.csv \
        --activites data/raw/finess/activites.csv \
        --out data/reference --n 300 --seed 42
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

EHPAD_CATEGORY = "500"  # TRE_R66: Etablissement d'hébergement pour personnes âgées dépendantes
ACTIVE_STATE = "A"
ACTIVITY_IN_SERVICE = "1"          # statut: active et mise en œuvre
FULL_BOARD = "11"                  # TRE_r404: hébergement complet ou internat
BED_ACTIVITIES = {"924", "657"}    # accueil permanent / temporaire pour personnes âgées
MAX_SHARE_PER_LEGAL_ENTITY = 0.02  # keeps the panel from mirroring any real operator group

# Mainland France plus Corsica, in WGS 84 degrees. Outside this box = suspicious position.
MAINLAND_BBOX = {"lat_min": 41.0, "lat_max": 51.5, "lon_min": -5.5, "lon_max": 10.0}

SITE_COLUMNS = [
    "finess_et", "finess_ej", "categorie", "etat", "date_ouverture", "date_fermeture",
    "secteur", "departement", "departement_libelle", "code_commune_insee",
    "latitude", "longitude", "latitude_longitude_origine",
]


def read_finess_csv(path: Path, usecols: list[str]) -> pd.DataFrame:
    """Read a FINESS CSV as text: FINESS numbers and department codes keep their leading zeros."""
    header = pd.read_csv(path, sep=";", encoding="utf-8-sig", nrows=0).columns
    missing = sorted(set(usecols) - set(header))
    if missing:
        # Fail loudly: a renamed source column must stop the pipeline, not yield empty fields.
        raise ValueError(f"{path.name}: expected columns not found: {missing}")
    return pd.read_csv(path, sep=";", encoding="utf-8-sig", dtype=str, usecols=usecols,
                       keep_default_na=False, na_values=[""])


def load_installed_capacity(path: Path | None) -> pd.Series:
    """Installed residential beds per establishment, the denominator of the CRJ.

    Summing every capacity line of a site overstates its beds, so only these lines count:
      - activity exercised (`niveau = exercee`) and in service (`statut = 1`);
      - full-board accommodation (`mode_fonctionnement = 11`), not day-care places;
      - permanent (924) or temporary (657) elderly accommodation.
    Excluded on purpose: 177 "Section Cure Médicale (dont)" is a subset of 924 (double count),
    961 PASA and day-care lines are places, not beds. 962 UHR is left out pending
    confirmation of whether FINESS counts it inside 924 (see docs/decision_log.md).
    """
    if path is None:
        return pd.Series(dtype="float64", name="capacite_installee")
    act = read_finess_csv(path, ["finess_et", "niveau", "statut", "activite",
                                 "mode_fonctionnement", "capacite_installee"])
    beds = act[
        (act["niveau"] == "exercee")
        & (act["statut"] == ACTIVITY_IN_SERVICE)
        & (act["mode_fonctionnement"] == FULL_BOARD)
        & (act["activite"].isin(BED_ACTIVITIES))
    ].copy()
    beds["capacite_installee"] = pd.to_numeric(beds["capacite_installee"], errors="coerce")
    return beds.groupby("finess_et")["capacite_installee"].sum(min_count=1)


def quality_checks(sites: pd.DataFrame) -> pd.DataFrame:
    """Return one row per (site, failed check). Nothing is silently fixed or dropped here."""
    lat = pd.to_numeric(sites["latitude"], errors="coerce")
    lon = pd.to_numeric(sites["longitude"], errors="coerce")
    mainland = ~sites["departement"].fillna("").str.match(r"^9[7-8]")
    out_of_box = mainland & lat.notna() & ~(
        lat.between(MAINLAND_BBOX["lat_min"], MAINLAND_BBOX["lat_max"])
        & lon.between(MAINLAND_BBOX["lon_min"], MAINLAND_BBOX["lon_max"])
    )
    checks = {
        "duplicate_finess_et": sites["finess_et"].duplicated(keep=False),
        "active_but_closing_date": sites["date_fermeture"].notna(),
        "missing_position": lat.isna() | lon.isna(),
        "position_computed_from_xy": sites["latitude_longitude_origine"].eq("calcul"),
        "position_outside_mainland_bbox": out_of_box,
        "missing_installed_capacity": sites["capacite_installee"].isna(),
        "zero_installed_capacity": sites["capacite_installee"].eq(0),
    }
    issues = [
        pd.DataFrame({"finess_et": sites.loc[mask, "finess_et"], "check": name})
        for name, mask in checks.items() if mask.any()
    ]
    return pd.concat(issues, ignore_index=True) if issues else pd.DataFrame(columns=["finess_et", "check"])


def sample_panel(eligible: pd.DataFrame, n: int, seed: int) -> pd.DataFrame:
    """Random panel spread across many legal entities, so it cannot be read as one real group."""
    cap = max(1, int(n * MAX_SHARE_PER_LEGAL_ENTITY))
    shuffled = eligible.sample(frac=1.0, random_state=seed)
    capped = shuffled.groupby("finess_ej", group_keys=False).head(cap)
    if len(capped) < n:
        raise ValueError(f"only {len(capped)} eligible sites after capping, {n} requested")
    return capped.head(n).sort_values(["departement", "finess_et"]).reset_index(drop=True)


def pseudonymise(panel: pd.DataFrame) -> pd.DataFrame:
    """Drop identifiers and round positions to ~1 km: sites stay realistic but not identifiable."""
    dim = pd.DataFrame({
        "site_id": [f"SITE_{i:04d}" for i in range(1, len(panel) + 1)],
        "secteur": panel["secteur"],
        "departement": panel["departement"],
        "departement_libelle": panel["departement_libelle"],
        "nb_lits_installes": panel["capacite_installee"].astype("Int64"),
        "annee_ouverture": pd.to_datetime(panel["date_ouverture"], errors="coerce").dt.year.astype("Int64"),
        "latitude": pd.to_numeric(panel["latitude"], errors="coerce").round(2),
        "longitude": pd.to_numeric(panel["longitude"], errors="coerce").round(2),
    })
    return dim


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--etablissements", type=Path, required=True)
    parser.add_argument("--activites", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--n", type=int, default=300)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--secteur", default="privé lucratif",
                        help="sector kept in the panel; empty string keeps all sectors")
    args = parser.parse_args()

    etab = read_finess_csv(args.etablissements, SITE_COLUMNS)
    ehpad = etab[(etab["categorie"] == EHPAD_CATEGORY) & (etab["etat"] == ACTIVE_STATE)].copy()
    ehpad = ehpad.join(load_installed_capacity(args.activites), on="finess_et")

    issues = quality_checks(ehpad)
    blocking = {"duplicate_finess_et", "missing_position", "missing_installed_capacity",
                "zero_installed_capacity", "position_outside_mainland_bbox"}
    rejected = set(issues.loc[issues["check"].isin(blocking), "finess_et"])

    eligible = ehpad[~ehpad["finess_et"].isin(rejected)]
    if args.secteur:
        eligible = eligible[eligible["secteur"] == args.secteur]
    panel = sample_panel(eligible, args.n, args.seed)

    args.out.mkdir(parents=True, exist_ok=True)
    pseudonymise(panel).to_csv(args.out / "dim_site.csv", index=False, encoding="utf-8")
    # The quality report keeps FINESS numbers: it describes the public source, not our panel.
    issues.to_csv(args.out / "data_quality_report.csv", index=False, encoding="utf-8")

    summary = {
        "run_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "parameters": {"n": args.n, "seed": args.seed, "secteur": args.secteur,
                       "max_share_per_legal_entity": MAX_SHARE_PER_LEGAL_ENTITY},
        "counts": {
            "establishments_read": len(etab),
            "active_ehpad": len(ehpad),
            "rejected_by_quality_checks": len(rejected),
            "eligible_after_sector_filter": len(eligible),
            "panel": len(panel),
        },
        "issues_by_check": issues["check"].value_counts().to_dict(),
        "source": "FINESS+ (ANS), Licence Ouverte 2.0 - see MENTION-SOURCE.txt for the snapshot date",
    }
    (args.out / "extraction_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2),
                                                      encoding="utf-8")
    print(json.dumps(summary["counts"], indent=2))


if __name__ == "__main__":
    main()
