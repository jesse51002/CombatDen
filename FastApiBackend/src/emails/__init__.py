"""Emails domain package.

CombatDen's OWN outbound mail: one ``email_log`` row per intended message,
claimed inside the caller's transaction and delivered detached afterwards.
Supabase Auth mail (GoTrue) and Stripe's connected-account mail are separate
channels that never pass through here.
"""

from pathlib import Path

# Register the Database schema package on sys.path before any submodule does a
# ``from schema.email import ...`` (this domain reuses the shared email enums).
import src.shared.db_schema_path  # noqa: F401, E402

SQL_DIR = Path(__file__).resolve().parent / "sql"
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"
