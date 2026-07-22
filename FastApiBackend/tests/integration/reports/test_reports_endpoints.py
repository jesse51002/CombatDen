"""Integration tests for the reports domain endpoints.

READ-ONLY against the single seeded gym (tests/seed_constants.py) — creates
nothing, so there is no ``created`` cleanup. The load-bearing test is the
numeric guard: it recomputes gross / refunds / net for the whole history with
its own inline aggregate and asserts equality with the report's ``summary.csv``,
so a money-math regression fails loudly here rather than in a gym's spreadsheet.

Requires the worktree backend running with the reports router (default
:8000 usually serves another checkout — set BACKEND_BASE_URL to the worktree's
own port, per tests/integration/conftest.py).

Run with the live server up:
    poetry run pytest tests/integration/reports/test_reports_endpoints.py -v
"""

import asyncio
import csv
import io
import uuid
import zipfile
from collections.abc import Callable
from decimal import Decimal

import httpx
from sqlalchemy import text

from src.shared.database import DirectDatabasePool

_REPORT_FILES = {
    "summary.csv",
    "payments.csv",
    "invoices.csv",
    "invoice_line_items.csv",
    "invoice_discounts.csv",
    "membership_changes.csv",
    "new_members.csv",
    "attendance.csv",
    "class_stats.csv",
}

_EXPORT_FILES = {
    "members.csv",
    "memberships.csv",
    "plans.csv",
    "plan_prices.csv",
    "invoices.csv",
    "charges.csv",
    "invoice_line_items.csv",
    "invoice_discounts.csv",
    "discounts.csv",
    "discount_values.csv",
    "membership_discounts.csv",
    "attendance.csv",
    "class_signups.csv",
    "classes.csv",
    "class_schedules.csv",
    "rewards.csv",
    "reward_redemptions.csv",
    "waivers.csv",
    "waiver_versions.csv",
    "waiver_signatures.csv",
    "authorized_payers.csv",
    "activities.csv",
    "employees.csv",
}


async def _req(fn: Callable, *args, **kwargs) -> httpx.Response:
    """Run a blocking ``httpx.Client`` call off the event loop thread.

    ``api`` is a plain sync client; calling it inline from an ``async def``
    test would block the loop the ``db_pool`` session also needs, so the HTTP
    call goes through ``asyncio.to_thread`` (mirrors the rewards-lifecycle
    integration suite).
    """
    return await asyncio.to_thread(fn, *args, **kwargs)


def _open_zip(response: httpx.Response) -> zipfile.ZipFile:
    return zipfile.ZipFile(io.BytesIO(response.content))


def _read_csv(zf: zipfile.ZipFile, name: str) -> list[list[str]]:
    text_body = zf.read(name).decode("utf-8-sig")
    return list(csv.reader(io.StringIO(text_body)))


class TestDownloadReport:
    """GET /api/v1/gyms/{gym_id}/reports/report."""

    def test_all_time_returns_200_zip(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        response = api.get(f"/api/v1/gyms/{gym_id}/reports/report")
        assert response.status_code == 200, response.text
        assert response.headers["content-type"] == "application/zip"
        cd = response.headers.get("content-disposition", "")
        assert "attachment" in cd
        assert "combatden_report_" in cd
        assert "all-time.zip" in cd

    def test_all_time_zip_has_every_report_file(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        response = api.get(f"/api/v1/gyms/{gym_id}/reports/report")
        assert response.status_code == 200, response.text
        with _open_zip(response) as zf:
            assert _REPORT_FILES.issubset(set(zf.namelist()))

    def test_month_returns_200_and_parses(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        response = api.get(
            f"/api/v1/gyms/{gym_id}/reports/report", params={"month": "2026-06"}
        )
        assert response.status_code == 200, response.text
        cd = response.headers["content-disposition"]
        assert "combatden_report_" in cd and "2026-06.zip" in cd
        with _open_zip(response) as zf:
            assert _REPORT_FILES.issubset(set(zf.namelist()))

    def test_bad_month_is_400(self, api: httpx.Client, gym_id: str) -> None:
        for bad in ("2026-13", "nonsense", "2026-6"):
            response = api.get(
                f"/api/v1/gyms/{gym_id}/reports/report", params={"month": bad}
            )
            assert response.status_code == 400, f"{bad}: {response.text}"

    def test_foreign_gym_is_403(self, api: httpx.Client) -> None:
        response = api.get(f"/api/v1/gyms/{uuid.uuid4()}/reports/report")
        assert response.status_code == 403, response.text


class TestDownloadFullExport:
    """GET /api/v1/gyms/{gym_id}/reports/full-export."""

    def test_returns_200_zip(self, api: httpx.Client, gym_id: str) -> None:
        response = api.get(f"/api/v1/gyms/{gym_id}/reports/full-export")
        assert response.status_code == 200, response.text
        assert response.headers["content-type"] == "application/zip"
        assert "combatden_export_" in response.headers.get(
            "content-disposition", ""
        )

    def test_zip_has_every_export_file(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        response = api.get(f"/api/v1/gyms/{gym_id}/reports/full-export")
        assert response.status_code == 200, response.text
        with _open_zip(response) as zf:
            assert _EXPORT_FILES.issubset(set(zf.namelist()))

    async def test_seeded_member_appears_in_members_csv(
        self, api: httpx.Client, gym_id: str, db_pool: DirectDatabasePool
    ) -> None:
        # A real seeded member's id must show up in the raw members dump.
        async with db_pool.session() as session:
            row = (
                await session.execute(
                    text(
                        "SELECT member_id FROM members "
                        "WHERE gym_id = :gym_id LIMIT 1"
                    ),
                    {"gym_id": gym_id},
                )
            ).fetchone()
        assert row is not None, "seed has no members for the gym"
        seeded_member_id = str(row[0])

        response = await _req(
            api.get, f"/api/v1/gyms/{gym_id}/reports/full-export"
        )
        assert response.status_code == 200, response.text
        with _open_zip(response) as zf:
            members_text = zf.read("members.csv").decode("utf-8-sig")
        assert seeded_member_id in members_text

    def test_foreign_gym_is_403(self, api: httpx.Client) -> None:
        response = api.get(f"/api/v1/gyms/{uuid.uuid4()}/reports/full-export")
        assert response.status_code == 403, response.text


class TestSummaryMoneyGuard:
    """The report's summary money must equal an independent DB aggregate."""

    async def test_all_time_gross_refunds_net_match_db(
        self, api: httpx.Client, gym_id: str, db_pool: DirectDatabasePool
    ) -> None:
        # Independent aggregate over the whole history (matches the all-time
        # report window) — the same pinned math the service computes in Python.
        async with db_pool.session() as session:
            row = (
                await session.execute(
                    text(
                        "SELECT "
                        "COALESCE(SUM(amount) FILTER "
                        "(WHERE kind='payment' AND status='succeeded'), 0) "
                        "AS gross, "
                        "COALESCE(SUM(amount) FILTER "
                        "(WHERE kind='refund' AND status='succeeded'), 0) "
                        "AS refunds "
                        "FROM member_charges WHERE gym_id = :gym_id"
                    ),
                    {"gym_id": gym_id},
                )
            ).fetchone()
        gross_cents, refund_cents = int(row[0]), int(row[1])
        expected_gross = (Decimal(gross_cents) / 100).quantize(Decimal("0.01"))
        expected_refunds = (Decimal(refund_cents) / 100).quantize(
            Decimal("0.01")
        )
        expected_net = (
            Decimal(gross_cents + refund_cents) / 100
        ).quantize(Decimal("0.01"))

        response = await _req(api.get, f"/api/v1/gyms/{gym_id}/reports/report")
        assert response.status_code == 200, response.text
        with _open_zip(response) as zf:
            summary = _read_csv(zf, "summary.csv")
        values = {row[0]: row[1] for row in summary[1:]}

        assert Decimal(values["gross_revenue"]) == expected_gross
        assert Decimal(values["refunds"]) == expected_refunds
        assert Decimal(values["net_revenue"]) == expected_net
        assert values["period"] == "all-time"
