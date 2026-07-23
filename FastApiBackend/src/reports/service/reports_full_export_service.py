"""Full raw-data export: every gym-owned table dumped to one zip of CSVs.

"Your data, yours to take." Raw values only — cents, UTC timestamps, UUIDs,
JSONB rendered as text — with NO transformation (that is the point: a faithful
dump). Each CSV's header is the query's own explicit column list (the SQL never
uses ``SELECT *``), so the header and the SELECT can never drift.

Excluded everywhere (see the SQL): ``members.video_profile_*`` (the RAG
embedding + summary), ``stripe_event_payload`` on invoices/charges, and the
tables that are pure internal infrastructure or a machine-derived cache
(``stripe_webhook_events``, ``resource_locks``, ``tasks``, the ``gym_video_*``
pool, and ``gym_growth_metrics`` — the Growth page's hourly-recomputed metric
cache, fully derivable from the source tables that ARE exported).
"""

import logging
from datetime import UTC, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text

from src.reports import SQL_DIR
from src.reports.service.reports_filenames import full_export_filename
from src.reports.service.reports_zip_builder import ReportsZipBuilder
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

# (csv file name inside the zip, SQL file). The CSV header is taken from the
# query's returned column names, so the SELECT column list IS the contract.
_EXPORTS: tuple[tuple[str, str], ...] = (
    ("members.csv", "export_members.sql"),
    ("memberships.csv", "export_memberships.sql"),
    ("plans.csv", "export_plans.sql"),
    ("plan_prices.csv", "export_plan_prices.sql"),
    ("invoices.csv", "export_invoices.sql"),
    ("charges.csv", "export_charges.sql"),
    ("invoice_line_items.csv", "export_line_items.sql"),
    ("invoice_discounts.csv", "export_invoice_discounts.sql"),
    ("discounts.csv", "export_discounts.sql"),
    ("discount_values.csv", "export_discount_values.sql"),
    ("membership_discounts.csv", "export_membership_discounts.sql"),
    ("attendance.csv", "export_attendance.sql"),
    ("class_signups.csv", "export_class_signups.sql"),
    ("classes.csv", "export_classes.sql"),
    ("class_schedules.csv", "export_class_schedules.sql"),
    ("rewards.csv", "export_rewards.sql"),
    ("reward_redemptions.csv", "export_reward_redemptions.sql"),
    ("waivers.csv", "export_waivers.sql"),
    ("waiver_versions.csv", "export_waiver_versions.sql"),
    ("waiver_signatures.csv", "export_waiver_signatures.sql"),
    ("authorized_payers.csv", "export_authorized_payers.sql"),
    ("activities.csv", "export_activities.sql"),
    ("employees.csv", "export_employees.sql"),
)


class ReportsFullExportService:
    """Builds the full raw-data export zip for a gym."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def build_export(self, gym_id: UUID) -> tuple[str, bytes]:
        """Build the export.

        Returns:
            ``(filename, zip_bytes)`` — the download name + the in-memory zip.
        """
        gym = await self._load_gym(gym_id)
        builder = ReportsZipBuilder()
        for csv_name, sql_file in _EXPORTS:
            header, rows = await self._dump(sql_file, gym_id)
            builder.add_csv(csv_name, header, rows)

        today_local = datetime.now(UTC).astimezone(ZoneInfo(gym["timezone"]))
        filename = full_export_filename(
            gym["gym_name"], gym_id, today_local.strftime("%Y%m%d")
        )
        return filename, builder.finish()

    async def _load_gym(self, gym_id: UUID) -> dict:
        """Load the gym's name + timezone (for the filename + local date)."""
        sql = load_sql(SQL_DIR / "reports_gym.sql")
        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(sql), {"gym_id": str(gym_id)}))
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError("Gym not found")
        return dict(row)

    async def _dump(
        self,
        sql_file: str,
        gym_id: UUID,
    ) -> tuple[tuple[str, ...], list[tuple]]:
        """Run one export query, returning its header + raw rows.

        The header is the query's own column names; each row is the mapping
        projected to that column order so the CSV columns match the SELECT.
        """
        sql = load_sql(SQL_DIR / sql_file)
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), {"gym_id": str(gym_id)})
            header = tuple(result.keys())
            rows = [
                tuple(mapping[col] for col in header)
                for mapping in result.mappings().all()
            ]
        return header, rows
