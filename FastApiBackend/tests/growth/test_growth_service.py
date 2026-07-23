"""Serve-path unit tests for ``GrowthService`` (mocked db_pool, no DB).

The serve path's whole job is fault tolerance: it must render what it can and
silently drop what it can't, so a rolling deploy or a retired metric never
blanks the Growth page.
"""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.growth.schema.growth_schema import GrowthMetricType
from src.growth.service.growth_service import GrowthService


def make_row(
    *,
    key: str,
    data: dict,
    computed_at: datetime | None = None,
    metric_type: str = "kpi_group",
) -> dict:
    """One ``gym_growth_metrics`` row as the read query returns it."""
    return {
        "key": key,
        "type": metric_type,
        "data": data,
        "computed_at": computed_at or datetime.now(UTC),
    }


def kpi_payload(value: float = 12) -> dict:
    """A minimal valid ``KpiGroupData`` payload."""
    return {
        "tiles": [
            {
                "key": "total",
                "label": "Total Members",
                "value": value,
                "unit": "count",
            }
        ]
    }


def breakdown_payload() -> dict:
    """A minimal valid ``BreakdownData`` payload."""
    return {
        "unit": "count",
        "items": [{"key": "plan", "label": "Unlimited", "value": 3}],
    }


def service_returning(rows: list[dict]) -> GrowthService:
    """A ``GrowthService`` whose single read returns ``rows``."""
    result = MagicMock()
    result.mappings.return_value.all.return_value = rows

    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(return_value=result)

    db_pool = MagicMock()
    db_pool.session.return_value = session
    return GrowthService(db_pool=db_pool)


@pytest.mark.asyncio
async def test_empty_cache_returns_no_metrics_and_null_computed_at() -> None:
    """A gym that has never been computed serves an empty, valid page."""
    response = await service_returning([]).get_growth(uuid4())

    assert response.metrics == []
    assert response.computed_at is None


@pytest.mark.asyncio
async def test_unknown_key_is_skipped() -> None:
    """A row for a retired metric is dropped instead of failing the page."""
    rows = [
        make_row(key="members_kpis", data=kpi_payload()),
        make_row(key="a_metric_that_no_longer_exists", data=kpi_payload()),
    ]

    response = await service_returning(rows).get_growth(uuid4())

    assert [metric.key for metric in response.metrics] == ["members_kpis"]


@pytest.mark.asyncio
async def test_malformed_payload_is_skipped() -> None:
    """A payload that no longer matches its model is dropped, not raised."""
    rows = [
        make_row(key="members_kpis", data=kpi_payload()),
        # members_by_plan is a breakdown; a kpi_group payload can't validate.
        make_row(key="members_by_plan", data=kpi_payload()),
    ]

    response = await service_returning(rows).get_growth(uuid4())

    assert [metric.key for metric in response.metrics] == ["members_kpis"]


@pytest.mark.asyncio
async def test_registry_type_wins_over_stored_type() -> None:
    """A stale write-time ``type`` column never overrides the registry."""
    rows = [
        make_row(
            key="members_by_plan",
            data=breakdown_payload(),
            metric_type="heatmap",
        )
    ]

    response = await service_returning(rows).get_growth(uuid4())

    assert response.metrics[0].type is GrowthMetricType.breakdown


@pytest.mark.asyncio
async def test_display_metadata_comes_from_the_registry() -> None:
    """Name / categories / order are attached at serve time, never stored."""
    rows = [make_row(key="members_by_plan", data=breakdown_payload())]

    metric = (await service_returning(rows).get_growth(uuid4())).metrics[0]

    assert metric.name == "Members by Plan"
    assert metric.order == 120
    assert [category.value for category in metric.categories] == ["members"]


@pytest.mark.asyncio
async def test_metrics_are_sorted_by_registry_order() -> None:
    """Rows come back unordered; the page is ordered by the registry."""
    rows = [
        make_row(key="members_by_plan", data=breakdown_payload()),
        make_row(key="members_kpis", data=kpi_payload()),
    ]

    response = await service_returning(rows).get_growth(uuid4())

    assert [metric.key for metric in response.metrics] == [
        "members_kpis",
        "members_by_plan",
    ]


@pytest.mark.asyncio
async def test_computed_at_is_the_minimum_of_surviving_metrics() -> None:
    """The page's staleness floor is the OLDEST metric that actually renders."""
    oldest = datetime.now(UTC) - timedelta(hours=5)
    newest = datetime.now(UTC)
    rows = [
        make_row(key="members_kpis", data=kpi_payload(), computed_at=newest),
        make_row(
            key="members_by_plan",
            data=breakdown_payload(),
            computed_at=oldest,
        ),
    ]

    response = await service_returning(rows).get_growth(uuid4())

    assert response.computed_at == oldest


@pytest.mark.asyncio
async def test_skipped_rows_do_not_affect_computed_at() -> None:
    """A dropped row's timestamp is not part of the staleness floor."""
    old_broken = datetime.now(UTC) - timedelta(days=3)
    fresh = datetime.now(UTC)
    rows = [
        make_row(key="members_kpis", data=kpi_payload(), computed_at=fresh),
        make_row(
            key="members_by_plan",
            data=kpi_payload(),
            computed_at=old_broken,
        ),
    ]

    response = await service_returning(rows).get_growth(uuid4())

    assert response.computed_at == fresh
