"""Hermetic regression guards for two SQL-templating footguns: the
`:param::type` bind cast, and a `{variable}` placeholder written inside a
`--` comment (which `load_sql`'s `format_map` expands anyway).

A production bug shipped where ``membership_plans_insert.sql`` cast bind
parameters with ``:waiver_ids::jsonb``.
SQLAlchemy's ``text()`` bind-parameter parser refuses to match a ``:name``
that is immediately followed by a colon (the ``::`` of a Postgres cast), so
those binds were passed through to asyncpg **literally** — producing
``PostgresSyntaxError: syntax error at or near ":"`` and a 500 on
``POST /api/v1/membership_plans/`` (which broke the seed at plan creation).

It then recurred in ``membership_plans_update.py``, which built the same
footgun **dynamically** — ``f"{col} = :{col}::jsonb"`` — where the bind name is
an interpolated placeholder. A ``.sql``-only scan can't see that, so this guard
covers both: production ``.sql`` files **and** ``:bind::cast`` patterns inside
``src`` Python string literals (including the ``:{placeholder}::cast`` form).

The fix is to always cast a bound value with ``CAST(:param AS TYPE)`` instead
of ``:param::type`` (a literal cast like ``'[]'::jsonb`` is fine — the hazard
is only a *bind parameter* immediately followed by ``::``).

This test is intentionally hermetic (no DB / Stripe / live backend) so it runs
in the default unit pass and catches the regression even when the live
integration tests are not run.
"""

import ast
import re
from pathlib import Path

# A bind param (``:name``) immediately followed by a Postgres cast (``::type``).
# This is the pattern SQLAlchemy's text() parser will NOT bind. Literal casts
# such as ``'[]'::jsonb`` do not match because they are not a ``:name`` bind.
_BIND_THEN_CAST = re.compile(r":[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_]")

# Same hazard built dynamically in Python: the bind name may be an interpolated
# ``{placeholder}`` (e.g. an f-string ``f"{col} = :{col}::jsonb"``) as well as a
# literal name. Run only over Python *string-ish* content in ``src``.
_PY_BIND_THEN_CAST = re.compile(
    r":(?:\{[^}]+\}|[A-Za-z_][A-Za-z0-9_]*)::[A-Za-z_]",
)

_SRC_DIR = Path(__file__).resolve().parent.parent / "src"


def test_no_bind_param_immediately_followed_by_cast() -> None:
    """No production .sql binds a param with a `::` cast (use CAST()).

    `--` comments are stripped before matching: a comment can't reach the
    SQLAlchemy parser, and the convention docs legitimately spell out the
    forbidden pattern in prose.
    """
    offenders: list[str] = []
    for sql_file in _SRC_DIR.rglob("*.sql"):
        text = sql_file.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            code = line.split("--", 1)[0]
            for match in _BIND_THEN_CAST.finditer(code):
                rel = sql_file.relative_to(_SRC_DIR.parent)
                offenders.append(f"{rel}:{lineno}: {match.group(0)}")

    assert not offenders, (
        "Bind parameter immediately followed by a `::` cast — SQLAlchemy "
        "text() will not bind it (asyncpg raises 'syntax error at or near "
        '":"'
        "'). Use CAST(:param AS TYPE) instead:\n  " + "\n  ".join(offenders)
    )


# A single-brace ``{name}`` template placeholder. ``load_sql`` runs
# ``str.format_map`` over the WHOLE file, so one of these inside a ``--``
# comment is expanded exactly like real SQL. ``{{name}}`` is the escape (it
# renders as literal ``{name}``) and is legitimate prose — e.g. the waiver
# template's ``{{placeholders}}`` — so it must NOT match.
_TEMPLATE_VAR_IN_COMMENT = re.compile(
    r"(?<!\{)\{[A-Za-z_][A-Za-z0-9_]*\}(?!\})",
)


def test_no_template_placeholder_inside_a_sql_comment() -> None:
    """No production .sql names a `{variable}` inside a `--` comment.

    ``load_sql``'s ``format_map`` does not know what a comment is. A comment
    that documents its own template variable in braces gets the whole injected
    SQL spliced into the comment block: the first injected line stays
    commented, every later line lands as bare SQL mid-file, and the query dies
    with an opaque ``syntax error`` pointing at code that reads as correct.
    This bit ``incomplete_view.sql``, whose header said "the predicate injected
    as ``{is_incomplete}``".

    Name the variable WITHOUT braces in prose. ``{{escaped}}`` is fine.
    """
    offenders: list[str] = []
    for sql_file in _SRC_DIR.rglob("*.sql"):
        text = sql_file.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            comment = line.split("--", 1)
            if len(comment) < 2:
                continue
            for match in _TEMPLATE_VAR_IN_COMMENT.finditer(comment[1]):
                rel = sql_file.relative_to(_SRC_DIR.parent)
                offenders.append(f"{rel}:{lineno}: {match.group(0)}")

    assert not offenders, (
        "A `{variable}` template placeholder appears inside a SQL `--` "
        "comment. load_sql format_maps the whole file, comments included, so "
        "the injected SQL is spliced into the comment and the file stops "
        "parsing. Drop the braces in prose:\n  " + "\n  ".join(offenders)
    )


def _docstring_constant_ids(tree: ast.Module) -> set[int]:
    """ids of the ``ast.Constant`` nodes that are docstrings (module /
    class / function first-statement strings) — prose, never SQL."""
    ids: set[int] = set()
    for node in ast.walk(tree):
        if not isinstance(
            node,
            (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef),
        ):
            continue
        body = node.body
        if (
            body
            and isinstance(body[0], ast.Expr)
            and isinstance(body[0].value, ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            ids.add(id(body[0].value))
    return ids


def _stringish_segments(tree: ast.Module) -> list[tuple[int, str]]:
    """Every runtime string in the file as ``(lineno, text)`` — plain
    string constants plus f-strings rendered with each interpolation as a
    ``{x}`` placeholder (so ``f":{col}::jsonb"`` scans as ``:{x}::jsonb``).
    Docstrings and ``#`` comments never appear (comments aren't in the
    AST; docstrings are excluded) — they may legitimately quote the
    forbidden pattern in prose, exactly like ``--`` comments in ``.sql``.
    """
    docstrings = _docstring_constant_ids(tree)
    joined_part_ids: set[int] = set()
    segments: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.JoinedStr):
            continue
        parts: list[str] = []
        for value in node.values:
            if isinstance(value, ast.Constant) and isinstance(
                value.value, str
            ):
                parts.append(value.value)
                joined_part_ids.add(id(value))
            else:
                parts.append("{x}")
        segments.append((node.lineno, "".join(parts)))
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Constant)
            and isinstance(node.value, str)
            and id(node) not in docstrings
            and id(node) not in joined_part_ids
        ):
            segments.append((node.lineno, node.value))
    return segments


def test_no_python_string_builds_bind_then_cast() -> None:
    """No production .py builds a `:param::type` bind (e.g. a SET-clause f-string).

    Catches the dynamic recurrence the .sql scan can't see, such as
    ``f"{col} = :{col}::jsonb"``. Use ``CAST(:{col} AS JSONB)`` instead.

    Scans actual runtime string constants (via ``ast``), so docstrings and
    ``#`` comments that spell out the forbidden pattern in prose don't
    false-positive — mirroring the ``--``-stripping in the .sql scan.
    """
    offenders: list[str] = []
    for py_file in _SRC_DIR.rglob("*.py"):
        text = py_file.read_text(encoding="utf-8")
        tree = ast.parse(text, filename=str(py_file))
        for lineno, segment in _stringish_segments(tree):
            for match in _PY_BIND_THEN_CAST.finditer(segment):
                rel = py_file.relative_to(_SRC_DIR.parent)
                offenders.append(f"{rel}:{lineno}: {match.group(0)}")

    assert not offenders, (
        "Python builds a bind param immediately followed by a `::` cast — "
        "SQLAlchemy text() will not bind it (asyncpg raises 'syntax error at "
        'near ":"'
        "'). Use CAST(:param AS TYPE) instead:\n  " + "\n  ".join(offenders)
    )
