"""Scheduled reconciler domain package.

A twice-daily, router-less billing safety-net: a thin orchestrator
(``ReconcilerService``) that runs independent step-services behind a global
sweep lock, started by APScheduler in the app lifespan. It reuses the existing
payment-sync engine and webhook absorption — it invents no new billing logic.
"""

from pathlib import Path

SQL_DIR = Path(__file__).resolve().parent / "sql"
