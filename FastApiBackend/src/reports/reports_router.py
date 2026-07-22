"""API routes for the reports domain.

Two read-only, gym-employee-gated (owner/admin) downloads:

- ``GET /{gym_id}/reports/report?month=YYYY-MM`` — the period operational
  report (month omitted => all-time).
- ``GET /{gym_id}/reports/full-export`` — the full raw-data export.

Both return an in-memory ``application/zip`` with a ``Content-Disposition``
attachment filename. Neither writes anything.
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.reports.schema.reports_schema import ReportMonth
from src.reports.service.reports_full_export_service import (
    ReportsFullExportService,
)
from src.reports.service.reports_period_service import ReportsPeriodService
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

reports_router = APIRouter(
    prefix="/api/v1/gyms",
    tags=["reports"],
)


def _zip_response(filename: str, zip_bytes: bytes) -> Response:
    """Wrap zip bytes in an attachment response.

    ``Content-Disposition`` must be exposed by CORS (see ``main.py``) for the
    browser to read the filename cross-origin.
    """
    return Response(
        content=zip_bytes,
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
        },
    )


@reports_router.get(
    "/{gym_id}/reports/report",
    summary="Download the period (monthly / all-time) operational report",
    description=(
        "A zip of CSVs covering the gym's finances, membership movement, and "
        "attendance/class stats for one calendar month (``?month=YYYY-MM``) "
        "or, when ``month`` is omitted, all-time. Human-facing: decimal "
        "dollars, gym-local datetimes, and a summary sheet. Owner/admin only."
    ),
    responses={
        200: {
            "content": {"application/zip": {}},
            "description": "The report zip",
        },
        400: {"description": "Invalid month (expected YYYY-MM)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def download_report(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    period_service: ReportsPeriodService = Depends(
        Provide[DependencyInjector.reports_period_service]
    ),
    month: str | None = Query(
        default=None,
        description="Report month as YYYY-MM; omit for all-time.",
    ),
) -> Response:
    """Build + return the period report zip."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    report_month: ReportMonth | None = None
    if month is not None:
        try:
            report_month = ReportMonth.parse(month)
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            ) from None

    try:
        filename, zip_bytes = await period_service.build_report(
            gym_id, report_month
        )
    except Exception:
        logger.error(
            "Failed to build report: gym_id=%s, month=%s",
            gym_id,
            month,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build report",
        ) from None

    return _zip_response(filename, zip_bytes)


@reports_router.get(
    "/{gym_id}/reports/full-export",
    summary="Download the full raw-data export",
    description=(
        "A zip of CSVs dumping every gym-owned table (members, memberships, "
        "invoices, charges, classes, attendance, waivers, and more) as raw "
        "values -- cents, UTC, UUIDs. \"Your data, yours to take.\" "
        "Owner/admin only."
    ),
    responses={
        200: {
            "content": {"application/zip": {}},
            "description": "The full-export zip",
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def download_full_export(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    export_service: ReportsFullExportService = Depends(
        Provide[DependencyInjector.reports_full_export_service]
    ),
) -> Response:
    """Build + return the full-export zip."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        filename, zip_bytes = await export_service.build_export(gym_id)
    except Exception:
        logger.error(
            "Failed to build full export: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build full export",
        ) from None

    return _zip_response(filename, zip_bytes)
