"""Download-filename derivation for the reports domain.

A pure, class-less concern module (a mapper by design, per the FastAPI service
layout rules). The slug + filenames are a v1 CONTRACT: renaming them is a
breaking change for anyone who has scripted around the download names, so they
live in one place.
"""

import re
from uuid import UUID

# Collapse every run of non-alphanumeric characters in the lowercased gym name
# to a single dash, then trim leading/trailing dashes.
_NON_ALNUM_RUN = re.compile(r"[^a-z0-9]+")


def gym_slug(gym_name: str, gym_id: UUID) -> str:
    """Derive a filename-safe slug from a gym name.

    Lowercase, non-alphanumeric runs -> ``-``, trimmed. If nothing survives
    (a name that is all punctuation/whitespace), fall back to ``gym-`` plus the
    first 8 hex characters of the gym id so the name is never empty.
    """
    slug = _NON_ALNUM_RUN.sub("-", gym_name.lower()).strip("-")
    return slug or f"gym-{gym_id.hex[:8]}"


def report_filename(gym_name: str, gym_id: UUID, period_slug: str) -> str:
    """The period-report zip name, e.g. ``combatden_report_iron-gym_2026-06.zip``.

    v1 contract: ``combatden_report_<slug>_<period>.zip``. ``period_slug`` is
    ``YYYY-MM`` for a month or ``all-time``.
    """
    return f"combatden_report_{gym_slug(gym_name, gym_id)}_{period_slug}.zip"


def full_export_filename(gym_name: str, gym_id: UUID, date_slug: str) -> str:
    """The full-export zip name, e.g. ``combatden_export_iron-gym_20260630.zip``.

    v1 contract: ``combatden_export_<slug>_<YYYYMMDD>.zip``. ``date_slug`` is
    the gym-local export date as ``YYYYMMDD`` (no dashes) so repeated exports
    on different days don't overwrite each other in Downloads.
    """
    return f"combatden_export_{gym_slug(gym_name, gym_id)}_{date_slug}.zip"
