"""Hermetic regression guard for the `:param::type` SQL bind footgun.

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


def test_no_python_string_builds_bind_then_cast() -> None:
    """No production .py builds a `:param::type` bind (e.g. a SET-clause f-string).

    Catches the dynamic recurrence the .sql scan can't see, such as
    ``f"{col} = :{col}::jsonb"``. Use ``CAST(:{col} AS JSONB)`` instead.
    """
    offenders: list[str] = []
    for py_file in _SRC_DIR.rglob("*.py"):
        text = py_file.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            for match in _PY_BIND_THEN_CAST.finditer(line):
                rel = py_file.relative_to(_SRC_DIR.parent)
                offenders.append(f"{rel}:{lineno}: {match.group(0)}")

    assert not offenders, (
        "Python builds a bind param immediately followed by a `::` cast — "
        "SQLAlchemy text() will not bind it (asyncpg raises 'syntax error at "
        'near ":"'
        "'). Use CAST(:param AS TYPE) instead:\n  " + "\n  ".join(offenders)
    )
