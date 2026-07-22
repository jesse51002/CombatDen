"""Guard test: the full-export SQL never SELECTS excluded columns or tables.

Iterates every ``export_*.sql`` file and asserts the forbidden strings never
appear in the EXECUTABLE SQL -- the RAG embedding + summary columns, the raw
Stripe event blobs, and the internal-only tables. ``--`` comment text is
stripped first, so a comment that documents *why* a column is excluded (e.g.
"EXCLUDES stripe_event_payload") is allowed while an actual selected column of
that name trips the test. A ``SELECT *`` that later re-introduces one of these
columns would also trip it.
"""

from src.reports import SQL_DIR

# Columns/tables that must NEVER be selected by an export query.
_FORBIDDEN_SUBSTRINGS = (
    "video_profile_summary",
    "video_profile_embedding",
    "video_profile_embedding_model",
    "video_profile_built_at",
    "stripe_event_payload",
    "stripe_webhook_events",
    "resource_locks",
    "gym_video_",
    "select *",
)


def _export_sql_files() -> list:
    return sorted(SQL_DIR.glob("export_*.sql"))


def _executable_sql(path) -> str:
    """The file's SQL with ``--`` comment tails removed, lowercased."""
    lines = []
    for line in path.read_text().splitlines():
        code = line.split("--", 1)[0]
        lines.append(code)
    return "\n".join(lines).lower()


class TestExportSqlGuard:
    """Every export query is free of the excluded columns/tables."""

    def test_export_files_exist(self) -> None:
        # Sanity: the glob actually found the export queries.
        assert len(_export_sql_files()) >= 20

    def test_no_forbidden_substrings(self) -> None:
        for path in _export_sql_files():
            sql = _executable_sql(path)
            for forbidden in _FORBIDDEN_SUBSTRINGS:
                assert forbidden not in sql, (
                    f"{path.name} selects forbidden '{forbidden}'"
                )

    def test_no_select_star(self) -> None:
        # Explicit column lists everywhere -- never SELECT *.
        for path in _export_sql_files():
            assert "select *" not in _executable_sql(path), path.name
