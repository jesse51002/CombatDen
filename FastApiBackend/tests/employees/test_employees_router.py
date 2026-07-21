"""Unit tests for the employees router (CRUD under /api/v1/employees).

Mocks at the same seam as the other router tests: the ``client`` fixture
(auth + db_pool overridden) and ``app.container.employees_service`` overridden
with a mock so no DB is touched. Asserts the router's status-code mapping
(service exceptions → HTTP codes) and that the owner/admin guard
(``verify_roles``) is awaited before the service runs.
"""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from schema.gym_employee import EmployeeType

import src.shared.db_schema_path  # noqa: F401  — resolves ``from schema.*``
from src.employees.employees_exceptions import (
    DuplicateEmployeeError,
    EmployeeNotFoundError,
    OwnerRowProtectedError,
)
from src.employees.schema.employees_schema import (
    EmployeeListResponse,
    EmployeeResponse,
    InviteStatus,
)
from src.main import app
from src.shared.auth import OWNER_ADMIN


def _employee_response(
    gym_id: UUID,
    *,
    employee_id: UUID | None = None,
    invite_status: InviteStatus = InviteStatus.pending,
) -> EmployeeResponse:
    return EmployeeResponse(
        employee_id=employee_id or uuid4(),
        gym_id=gym_id,
        employee_type=EmployeeType.front_desk,
        first_name="Ada",
        last_name="Lovelace",
        phone=None,
        email="ada@example.com",
        employee_pic_url=None,
        employee_public_description=None,
        created_at=datetime.now(UTC),
        invite_status=invite_status,
    )


@pytest.fixture
def employees_service_mock():
    """Override the DI-wired ``EmployeesService`` with a mock for one test."""
    service = MagicMock()
    app.container.employees_service.override(service)
    try:
        yield service
    finally:
        app.container.employees_service.reset_override()


# ── GET ───────────────────────────────────────────────────────────


def test_list_employees_returns_list(
    client, auth_headers, auth_mock, employees_service_mock, fake_gym_id
):
    employees_service_mock.list_employees = AsyncMock(
        return_value=EmployeeListResponse(
            employees=[_employee_response(UUID(fake_gym_id))]
        )
    )

    resp = client.get(f"/api/v1/employees/{fake_gym_id}", headers=auth_headers)

    assert resp.status_code == 200
    assert len(resp.json()["employees"]) == 1
    auth_mock.verify_roles.assert_awaited()


# ── POST ──────────────────────────────────────────────────────────


def _create_body() -> dict:
    return {
        "employee_type": "front_desk",
        "first_name": "Ada",
        "last_name": "Lovelace",
        "email": "ada@example.com",
    }


def test_create_employee_returns_201(
    client, auth_headers, auth_mock, employees_service_mock, fake_gym_id
):
    employees_service_mock.create_employee = AsyncMock(
        return_value=_employee_response(UUID(fake_gym_id))
    )

    resp = client.post(
        f"/api/v1/employees/{fake_gym_id}",
        json=_create_body(),
        headers=auth_headers,
    )

    assert resp.status_code == 201, resp.text
    assert resp.json()["invite_status"] == "pending"
    auth_mock.verify_roles.assert_awaited()
    employees_service_mock.create_employee.assert_awaited_once()


def test_create_employee_duplicate_maps_409(
    client, auth_headers, employees_service_mock, fake_gym_id
):
    employees_service_mock.create_employee = AsyncMock(
        side_effect=DuplicateEmployeeError("An employee with this email exists")
    )

    resp = client.post(
        f"/api/v1/employees/{fake_gym_id}",
        json=_create_body(),
        headers=auth_headers,
    )

    assert resp.status_code == 409


def test_create_employee_value_error_maps_400(
    client, auth_headers, employees_service_mock, fake_gym_id
):
    employees_service_mock.create_employee = AsyncMock(
        side_effect=ValueError("Invalid employee data")
    )

    resp = client.post(
        f"/api/v1/employees/{fake_gym_id}",
        json=_create_body(),
        headers=auth_headers,
    )

    assert resp.status_code == 400


# ── PUT ───────────────────────────────────────────────────────────


def test_update_employee_returns_200(
    client, auth_headers, auth_mock, employees_service_mock, fake_gym_id
):
    employee_id = uuid4()
    employees_service_mock.update_employee = AsyncMock(
        return_value=_employee_response(
            UUID(fake_gym_id), employee_id=employee_id
        )
    )

    resp = client.put(
        f"/api/v1/employees/{fake_gym_id}/{employee_id}",
        json={"data": {"first_name": "Grace"}},
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    # get_employee_id IS the PUT's authorization step: it applies the same
    # owner/admin gate as verify_roles and additionally returns the caller's
    # own employee id for the owner-self rule, so the route calls only it.
    auth_mock.get_employee_id.assert_awaited()
    assert auth_mock.get_employee_id.await_args.args[2] == OWNER_ADMIN
    auth_mock.verify_roles.assert_not_awaited()


def test_update_employee_owner_protected_maps_403(
    client, auth_headers, employees_service_mock, fake_gym_id
):
    employees_service_mock.update_employee = AsyncMock(
        side_effect=OwnerRowProtectedError("owner row protected")
    )

    resp = client.put(
        f"/api/v1/employees/{fake_gym_id}/{uuid4()}",
        json={"data": {"first_name": "Grace"}},
        headers=auth_headers,
    )

    assert resp.status_code == 403


def test_update_employee_not_found_maps_404(
    client, auth_headers, employees_service_mock, fake_gym_id
):
    employees_service_mock.update_employee = AsyncMock(
        side_effect=EmployeeNotFoundError("not found")
    )

    resp = client.put(
        f"/api/v1/employees/{fake_gym_id}/{uuid4()}",
        json={"data": {"first_name": "Grace"}},
        headers=auth_headers,
    )

    assert resp.status_code == 404


# ── DELETE ────────────────────────────────────────────────────────


def test_delete_employee_returns_204(
    client, auth_headers, auth_mock, employees_service_mock, fake_gym_id
):
    employees_service_mock.archive_employee = AsyncMock(return_value=None)

    resp = client.delete(
        f"/api/v1/employees/{fake_gym_id}/{uuid4()}", headers=auth_headers
    )

    assert resp.status_code == 204
    auth_mock.verify_roles.assert_awaited()
    employees_service_mock.archive_employee.assert_awaited_once()


def test_delete_owner_maps_403(
    client, auth_headers, employees_service_mock, fake_gym_id
):
    employees_service_mock.archive_employee = AsyncMock(
        side_effect=OwnerRowProtectedError("The gym owner cannot be archived.")
    )

    resp = client.delete(
        f"/api/v1/employees/{fake_gym_id}/{uuid4()}", headers=auth_headers
    )

    assert resp.status_code == 403
