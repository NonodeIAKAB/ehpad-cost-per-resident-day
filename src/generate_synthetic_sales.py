"""Generate the synthetic source files of the CRJ project from the FINESS site panel.

Reproduces the *shape* of the real mission (grain, product families, CRJ categories,
share of out-of-scope sales, credit notes, messy reference data, an occupancy file
whose layout changes every quarter). Every value - volume, price, target, split - is
invented. See docs/decision_log.md, D-008 and D-009.

Outputs (in --out, default data/synthetic):
    sales/sales_AAAA_MM.csv          monthly ERP export: ';' separator, decimal comma
    occupancy/occupancy_AAAA_Qn.xlsx client occupancy file, layout differs each quarter
    ref/dim_product.csv              product master, some new SKUs not yet categorised
    ref/dim_account.csv              billing accounts, segment, linen internalisation
    ref/excluded_accounts.csv        accounts the business asks to keep out of the CRJ
    ref/crj_target.csv               target CRJ per category, fixed / variable split
    _ground_truth/anomalies.csv      every defect injected on purpose, for the tests

Usage:
    python src/generate_synthetic_sales.py --sites data/reference/dim_site.csv --seed 42
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

START, END = "2023-01-01", "2025-12-01"   # 36 months: enough history for the forecast project

# family -> (CRJ category, number of SKUs, median unit price EUR, monthly units per 100 occupied beds)
FAMILIES = {
    "HEBERGEMENT": ("CRJ Hebergement", 90, 18.0, 9.0),
    "LINGERIE":    ("CRJ Lingerie", 70, 42.0, 2.2),
    "PLONGE":      ("CRJ Plonge", 70, 26.0, 2.4),
    "CUISINE":     ("CRJ Cuisine", 50, 21.0, 1.6),
    "USTENSILES":  ("CRJ autres univers", 90, 7.5, 3.0),
    "MACHINES":    ("Hors CRJ", 25, 380.0, 0.05),
    "DOSEURS":     ("Hors CRJ", 25, 95.0, 0.15),
    "SERVICES & CONSULTING": ("Hors CRJ", 15, 160.0, 0.10),
}
SHARE_OUT_OF_SCOPE_IN_CORE = 0.25   # some core-family SKUs are billed outside the CRJ scope
SHARE_NEW_UNCATEGORISED = 0.03      # new SKUs missing a CRJ category in the master
YEARLY_PRICE_INCREASE = 0.035
CREDIT_NOTE_RATE = 0.004
DUPLICATE_LINE_RATE = 0.001
N_EXCLUDED_ACCOUNTS = 12

# Invented targets, EUR per occupied resident-day, with the share that scales with installed capacity.
TARGETS = [
    ("CRJ Hebergement", 0.110, 0.35),
    ("CRJ Plonge", 0.055, 0.60),
    ("CRJ Cuisine", 0.035, 1.00),
    ("CRJ autres univers", 0.030, 1.00),
]
# Linen target depends on how much of the linen the site washes in-house.
LINEN_TARGETS = {"INTERNE": 0.160, "PARTIEL": 0.095, "EXTERNE": 0.025}

# Clean value -> messy variants seen in hand-maintained client files.
MESSY_INTERNALISATION = {
    "INTERNE": ["INTERNE", "Interne", "INTERNE MUTUALISATION"],
    "PARTIEL": ["PARTIEL", "partiel ", "PARTIEL MUTUALISATION"],
    "EXTERNE": ["EXTERNE", "Externe"],
}
SEGMENTS = ["Historique", "Acquisition 2019", "Acquisition 2022", "Résidences services"]

FR_MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
             "septembre", "octobre", "novembre", "décembre"]


def build_products(rng: np.random.Generator) -> tuple[pd.DataFrame, list[dict]]:
    rows, anomalies, n = [], [], 0
    for family, (category, count, price, _) in FAMILIES.items():
        for _ in range(count):
            n += 1
            sku = f"SKU{100000 + n}"
            crj = category
            if category != "Hors CRJ" and rng.random() < SHARE_OUT_OF_SCOPE_IN_CORE:
                crj = "Hors CRJ"
            if rng.random() < SHARE_NEW_UNCATEGORISED:
                anomalies.append({"table": "dim_product", "key": sku, "anomaly": "uncategorised_sku",
                                  "expected_handling": "list for the account manager, keep out of CRJ until categorised"})
                crj = None
            rows.append({"sku": sku, "designation": f"{family.title()} - article {n:03d}",
                         "product_family": family, "crj_category": crj,
                         "unit_price_2023": round(float(price * rng.lognormal(0, 0.45)), 2)})
    return pd.DataFrame(rows), anomalies


def build_accounts(sites: pd.DataFrame, rng: np.random.Generator) -> tuple[pd.DataFrame, list[dict]]:
    rows, anomalies = [], []
    for i, site in enumerate(sites.itertuples(), start=1):
        linen = rng.choice(list(LINEN_TARGETS), p=[0.55, 0.30, 0.15])
        label = rng.choice(MESSY_INTERNALISATION[linen])
        if rng.random() < 0.03:
            label = "Non renseigné"
            anomalies.append({"table": "dim_account", "key": site.site_id, "anomaly": "missing_linen_status",
                              "expected_handling": "flag; apply the most conservative linen target"})
        rows.append({"account_id": f"ACC{700000 + i * 7}", "site_id": site.site_id,
                     "segment": rng.choice(SEGMENTS, p=[0.65, 0.15, 0.12, 0.08]),
                     "linen_internalisation": label, "linen_internalisation_true": linen})
        if rng.random() < 0.04:   # a few sites are billed on a second account
            rows.append({**rows[-1], "account_id": f"ACC{900000 + i * 7}"})
    return pd.DataFrame(rows), anomalies


def build_occupancy(sites: pd.DataFrame, months: pd.DatetimeIndex, rng: np.random.Generator) -> pd.DataFrame:
    base_rate = rng.beta(30, 2.5, len(sites))          # mean ~0.92
    frames = []
    for site, beds, rate in zip(sites["site_id"], sites["nb_lits_installes"], base_rate):
        seasonal = 1 - 0.015 * np.cos((months.month - 1) / 12 * 2 * np.pi + np.pi)  # dip in winter
        occ = np.clip(rate * seasonal + rng.normal(0, 0.015, len(months)), 0.6, 1.0)
        frames.append(pd.DataFrame({"site_id": site, "month": months, "installed_beds": beds,
                                    "occupied_beds": np.round(beds * occ, 1)}))
    return pd.concat(frames, ignore_index=True)


def build_sales(sites, accounts, products, occupancy, months, rng):
    """Monthly lines site x SKU x month. Spend follows occupied beds, a site efficiency factor and price."""
    main_account = accounts.drop_duplicates("site_id").set_index("site_id")["account_id"]
    extra_account = accounts[accounts.duplicated("site_id")].set_index("site_id")["account_id"]
    linen = accounts.drop_duplicates("site_id").set_index("site_id")["linen_internalisation_true"]
    linen_factor = {"INTERNE": 1.0, "PARTIEL": 0.55, "EXTERNE": 0.12}
    occ = occupancy.set_index(["site_id", "month"])["occupied_beds"]
    by_family = {f: g for f, g in products.groupby("product_family")}

    lines = []
    for site in sites["site_id"]:
        efficiency = rng.lognormal(0, 0.18)          # some sites overspend: what the CRJ should reveal
        basket = pd.concat([g.sample(n=max(1, int(len(g) * rng.uniform(0.08, 0.16))), random_state=rng.integers(1e9))
                            for g in by_family.values()])
        for month in months:
            beds = occ[(site, month)]
            years = (month.year - 2023) + (month.month - 1) / 12
            for p in basket.itertuples():
                rate = FAMILIES[p.product_family][3] / len(by_family[p.product_family]) * 10
                if p.product_family == "LINGERIE":
                    rate *= linen_factor[linen[site]]
                qty = rng.poisson(max(rate * beds / 100 * efficiency, 0.01) * 3)
                if qty == 0:
                    continue
                price = p.unit_price_2023 * (1 + YEARLY_PRICE_INCREASE) ** years
                account = extra_account.get(site, main_account[site]) if rng.random() < 0.3 else main_account[site]
                lines.append((account, p.sku, month, qty, round(qty * price, 2)))
    sales = pd.DataFrame(lines, columns=["account_id", "sku", "month", "quantity", "net_invoice_value"])
    return sales


def calibrate_to_targets(sales, accounts, products, occupancy, rng) -> pd.DataFrame:
    """Rescale spend so the median site sits close to its target CRJ.

    Without this, CRJ levels depend on arbitrary consumption rates. After it, roughly half
    of the sites are above target, with a spread driven by each site's efficiency factor.
    """
    site_of = accounts.drop_duplicates("account_id").set_index("account_id")["site_id"]
    linen = accounts.drop_duplicates("site_id").set_index("site_id")["linen_internalisation_true"]
    category = products.set_index("sku")["crj_category"]
    resident_days = (occupancy.assign(days=occupancy["month"].dt.days_in_month)
                     .eval("occupied_beds * days").groupby(occupancy["site_id"]).sum())
    target = {c: t for c, t, _ in TARGETS}
    df = sales.assign(site_id=sales["account_id"].map(site_of), crj=sales["sku"].map(category))
    df["group"] = np.where(df["crj"] == "CRJ Lingerie", "CRJ Lingerie|" + df["site_id"].map(linen), df["crj"])
    spend = df.groupby(["group", "site_id"])["net_invoice_value"].sum()
    crj = spend / resident_days.reindex(spend.index.get_level_values("site_id")).to_numpy()
    factors = {}
    for group, values in crj.groupby(level="group"):
        cat, _, lin = group.partition("|")
        goal = LINEN_TARGETS[lin] if lin else target.get(cat)
        if goal:
            factors[group] = goal * rng.uniform(1.00, 1.06) / values.median()   # slight overall overspend
    scale = df["group"].map(factors).fillna(1.0)
    return sales.assign(net_invoice_value=(sales["net_invoice_value"] * scale).round(2))


def inject_sales_defects(sales: pd.DataFrame, rng) -> tuple[pd.DataFrame, list[dict]]:
    anomalies = []
    credit_idx = sales.sample(frac=CREDIT_NOTE_RATE, random_state=rng.integers(1e9)).index
    credits = sales.loc[credit_idx].copy()
    credits[["quantity", "net_invoice_value"]] *= -1
    dup = sales.sample(frac=DUPLICATE_LINE_RATE, random_state=rng.integers(1e9))
    for r in credits.itertuples():
        anomalies.append({"table": "sales", "key": f"{r.account_id}|{r.sku}|{r.month:%Y-%m}",
                          "anomaly": "credit_note", "expected_handling": "keep: nets the original invoice"})
    for r in dup.itertuples():
        anomalies.append({"table": "sales", "key": f"{r.account_id}|{r.sku}|{r.month:%Y-%m}",
                          "anomaly": "exact_duplicate_line", "expected_handling": "flag for review, do not drop silently"})
    return pd.concat([sales, credits, dup], ignore_index=True), anomalies


def write_sales_exports(sales: pd.DataFrame, out: Path) -> None:
    """One file per month, French ERP style: ';' separator, decimal comma, French month name."""
    (out / "sales").mkdir(parents=True, exist_ok=True)
    for month, chunk in sales.groupby("month"):
        export = chunk.assign(ANNEE=month.year, MOIS=FR_MONTHS[month.month - 1]).rename(columns={
            "account_id": "CODE CLIENT", "sku": "SKU", "quantity": "Volume", "net_invoice_value": "Net Invoice Value"})
        export[["CODE CLIENT", "SKU", "ANNEE", "MOIS", "Volume", "Net Invoice Value"]].to_csv(
            out / "sales" / f"sales_{month:%Y_%m}.csv", sep=";", decimal=",", index=False, encoding="utf-8-sig")


def write_occupancy_files(occupancy: pd.DataFrame, accounts: pd.DataFrame, out: Path, rng) -> list[dict]:
    """Quarterly client files. The layout rotates between three versions, as it did in real life."""
    (out / "occupancy").mkdir(parents=True, exist_ok=True)
    code = accounts.drop_duplicates("site_id").set_index("site_id")["account_id"]
    anomalies = []
    occ = occupancy.assign(quarter=occupancy["month"].dt.to_period("Q"))
    for i, (quarter, q) in enumerate(occ.groupby("quarter")):
        q = q.copy()
        q["Code client"] = q["site_id"].map(code)
        missing = q.sample(n=3, random_state=rng.integers(1e9)).index
        for r in q.loc[missing].itertuples():
            anomalies.append({"table": "occupancy", "key": f"{r.site_id}|{r.month:%Y-%m}",
                              "anomaly": "missing_occupancy", "expected_handling": "fall back to the site's quarter average, flag it"})
        q.loc[missing, "occupied_beds"] = np.nan
        path = out / "occupancy" / f"occupancy_{quarter.year}_Q{quarter.quarter}.xlsx"
        layout = i % 3
        if layout == 0:     # long table, clean headers
            df = q.rename(columns={"installed_beds": "Nb lits total", "occupied_beds": "Nb lits occupés"})
            df["Mois"] = df["month"].dt.strftime("%Y-%m")
            df[["Code client", "Mois", "Nb lits total", "Nb lits occupés"]].to_excel(path, index=False)
        elif layout == 1:   # wide: one column per month, different header spelling
            wide = q.assign(col=q["month"].dt.strftime("%m/%Y")).pivot(
                index="Code client", columns="col", values="occupied_beds")
            beds = q.drop_duplicates("Code client").set_index("Code client")["installed_beds"]
            df = wide.join(beds).reset_index()
            df = df[["Code client", "installed_beds", *wide.columns]]
            df.columns = ["CODE CLIENT", "NB LITS"] + [f"Occupés {c}" for c in wide.columns]
            df.to_excel(path, index=False)
        else:               # long, but with a title block above the header and an occupancy rate
            df = q.assign(**{"Taux occupation": (q["occupied_beds"] / q["installed_beds"]).round(4)})
            df = df.rename(columns={"installed_beds": "Lits installés"})
            df["Période"] = df["month"].dt.strftime("%d/%m/%Y")
            with pd.ExcelWriter(path) as xl:
                pd.DataFrame([[f"Taux d'occupation - T{quarter.quarter} {quarter.year}"], ["Source : direction des opérations"], [None]]
                             ).to_excel(xl, index=False, header=False)
                df[["Code client", "Période", "Lits installés", "Taux occupation"]].to_excel(xl, index=False, startrow=3)
    return anomalies


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sites", type=Path, default=Path("data/reference/dim_site.csv"))
    parser.add_argument("--out", type=Path, default=Path("data/synthetic"))
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()
    rng = np.random.default_rng(args.seed)

    sites = pd.read_csv(args.sites, dtype={"site_id": str, "departement": str})
    months = pd.date_range(START, END, freq="MS")

    products, a_prod = build_products(rng)
    accounts, a_acc = build_accounts(sites, rng)
    occupancy = build_occupancy(sites, months, rng)
    sales = build_sales(sites, accounts, products, occupancy, months, rng)
    sales = calibrate_to_targets(sales, accounts, products, occupancy, rng)
    sales, a_sales = inject_sales_defects(sales, rng)

    excluded = accounts.sample(n=N_EXCLUDED_ACCOUNTS, random_state=rng.integers(1e9))
    excluded = pd.DataFrame({"account_id": excluded["account_id"],
                             "reason": rng.choice(["litige", "fermeture", "hors périmètre"], N_EXCLUDED_ACCOUNTS),
                             "since": rng.choice(pd.date_range("2023-06-01", "2025-06-01", freq="QS"), N_EXCLUDED_ACCOUNTS)})
    a_excl = [{"table": "excluded_accounts", "key": a, "anomaly": "excluded_account_still_billed",
               "expected_handling": "move its sales to 'Hors CRJ'"} for a in excluded["account_id"]]

    targets = [{"crj_category": c, "linen_internalisation": None, "target_eur_per_resident_day": t,
                "share_fixed": f, "share_variable": round(1 - f, 2)} for c, t, f in TARGETS]
    targets += [{"crj_category": "CRJ Lingerie", "linen_internalisation": k, "target_eur_per_resident_day": v,
                 "share_fixed": 0.40, "share_variable": 0.60} for k, v in LINEN_TARGETS.items()]

    ref = args.out / "ref"
    (args.out / "_ground_truth").mkdir(parents=True, exist_ok=True)
    ref.mkdir(parents=True, exist_ok=True)
    write_sales_exports(sales, args.out)
    a_occ = write_occupancy_files(occupancy, accounts, args.out, rng)
    products.drop(columns="unit_price_2023").to_csv(ref / "dim_product.csv", index=False)
    accounts.drop(columns="linen_internalisation_true").to_csv(ref / "dim_account.csv", index=False)
    excluded.to_csv(ref / "excluded_accounts.csv", index=False)
    pd.DataFrame(targets).to_csv(ref / "crj_target.csv", index=False)
    occupancy.to_csv(args.out / "_ground_truth" / "occupancy_true.csv", index=False)
    pd.DataFrame(a_prod + a_acc + a_sales + a_excl + a_occ).to_csv(
        args.out / "_ground_truth" / "anomalies.csv", index=False)

    print(f"{len(sales):,} sales lines, {sales['sku'].nunique()} SKUs, {len(months)} months, "
          f"{sales['net_invoice_value'].sum():,.0f} EUR")


if __name__ == "__main__":
    main()
