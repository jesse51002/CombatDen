"""Smoke + auth tests for the growth router."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from fastapi import HTTPException, status


def make_metric_row(
    *,
    key: str,
    data: dict,
    metric_type: str = "kpi_group",
    computed_at: datetime | None = None,
) -> dict:
    """A ``gym_growth_metrics`` row as ``list_metrics_for_gym.sql`` returns it."""
    return {
        "key": key,
        "type": metric_type,
        "data": data,
        "computed_at": computed_at or datetime.now(UTC),
    }


def kpi_payload() -> dict:
    """A minimal valid ``KpiGroupData`` payload."""
    return {
        "tiles": [
            {
                "key": "total",
                "label": "Total Members",
                "value": 42,
                "unit": "count",
            }
        ]
    }


def stub_rows(db_pool_mock: MagicMock, rows: list[dict]) -> None:
    """Make the single read in the serve path return ``rows``."""
    result = MagicMock()
    result.mappings.return_value.all.return_value = rows
    db_pool_mock.session.return_value.execute = AsyncMock(return_value=result)


def test_get_growth_returns_the_page(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """GET /api/v1/growth/?gym_id=... serves the cached metrics."""
    computed_at = datetime.now(UTC)
    stub_rows(
        db_pool_mock,
        [
            make_metric_row(
                key="members_kpis",
                data=kpi_payload(),
                computed_at=computed_at,
            )
        ],
    )

    response = client.get(
        f"/api/v1/growth/?gym_id={fake_gym_id}",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["computed_at"] is not None
    assert len(body["metrics"]) == 1
    metric = body["metrics"][0]
    assert metric["key"] == "members_kpis"
    assert metric["name"] == "Members"
    assert metric["type"] == "kpi_group"
    assert metric["order"] == 20
    assert metric["categories"] == ["overview", "members"]
    assert metric["data"]["tiles"][0]["value"] == 42


def test_get_growth_empty_cache_is_a_valid_empty_page(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """A never-computed gym gets an empty page, not an error."""
    stub_rows(db_pool_mock, [])

    response = client.get(
        f"/api/v1/growth/?gym_id={fake_gym_id}",
        headers=auth_headers,
    )

    assert response.status_code == 200
    assert response.json() == {"computed_at": None, "metrics": []}


def test_get_growth_requires_authentication(client, fake_gym_id):
    """No bearer token -> 401 before any service call."""
    response = client.get(f"/api/v1/growth/?gym_id={fake_gym_id}")

    assert response.status_code == status.HTTP_401_UNAUTHORIZED


def test_get_growth_rejects_non_staff(
    client, auth_mock, auth_headers, fake_gym_id
):
    """A caller who is not an employee of the gym -> 403."""
    auth_mock.verify_gym_employee = AsyncMock(
        side_effect=HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized for this gym",
        )
    )

    response = client.get(
        f"/api/v1/growth/?gym_id={fake_gym_id}",
        headers=auth_headers,
    )

    assert response.status_code == status.HTTP_403_FORBIDDEN


def test_get_growth_maps_a_read_failure_to_500(
    client, db_pool_mock, auth_headers
):
    """A failing read is logged and surfaced as 500, never a proxy-retry 5xx."""
    db_pool_mock.session.return_value.execute = AsyncMock(
        side_effect=RuntimeError("database is down")
    )

    response = client.get(
        f"/api/v1/growth/?gym_id={uuid4()}",
        headers=auth_headers,
    )

    assert response.status_code == status.HTTP_500_INTERNAL_SERVER_ERROR
