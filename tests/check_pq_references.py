"""Static check of the Power Query files: every name used must exist.

A name used in a query must be either a step defined in that query, another query of the
powerquery/ folder, or an M keyword. Catches the "L'importation X ne correspond à aucune
exportation" error before pasting anything into Excel.

Usage:
    python tests/check_pq_references.py            (exit code 1 if a name is unknown)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

PQ_DIR = Path(__file__).resolve().parent.parent / "powerquery"
KEYWORDS = {"let", "in", "each", "if", "then", "else", "and", "or", "not", "type", "null", "true",
            "false", "as", "error", "meta", "table", "text", "list", "number", "binary", "date",
            "logical", "any", "try", "otherwise"}


def strip_noise(code: str) -> str:
    """Remove comments, string literals and [field] accesses, which are not query or step names."""
    code = re.sub(r"//[^\n]*", "", code)
    code = re.sub(r'"(?:[^"]|"")*"', '""', code)
    return re.sub(r"\[[^\[\]]*\]", "[]", code)


def unknown_names(code: str, queries: set[str]) -> list[str]:
    code = strip_noise(code)
    defined = set(re.findall(r"^\s*([A-Za-z_]\w*)\s*=(?!>)", code, re.M))
    used = set(re.findall(r"(?<![\.\w#])([A-Za-z_]\w*)\b(?!\s*\.)", code))
    # Capitalised names only: steps and queries are capitalised here, function parameters are not.
    return sorted(u for u in used - defined - queries - KEYWORDS
                  if u[0].isupper() and not re.search(rf"\b{u}\.", code))


def main() -> int:
    files = sorted(PQ_DIR.glob("*.pq"))
    queries = {f.stem for f in files}
    problems = {f.name: bad for f in files if (bad := unknown_names(f.read_text(encoding="utf-8"), queries))}
    for name, bad in problems.items():
        print(f"{name}: noms inconnus {bad}")
    print(f"{len(files)} requêtes contrôlées, {len(problems)} en erreur")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
