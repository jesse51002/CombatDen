"""Reports domain package.

Two read-only, in-memory zip endpoints for gym owners/admins:

- a per-month (or all-time) operational report (human-facing: decimal
  dollars, gym-local datetimes, a summary sheet), and
- a full raw data export ("your data, yours to take": cents, UTC, UUIDs).

Both are gym-employee gated and produce no side effects.
"""

from pathlib import Path

SQL_DIR = Path(__file__).resolve().parent / "sql"
