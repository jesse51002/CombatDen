"""Unit tests for the employee-update owner-row guard + column guard.

``EmployeesUpdate._enforce_owner_rules`` is a pure staticmethod, so it is
tested directly (no DB). Also asserts ``validate_mutable_columns`` rejects an
immutable ``gym_employees`` column and passes a mutable one.
"""

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from schema.gym_employee import EmployeeType
from schema.immutable_columns import GYM_EMPLOYEES

import src.shared.db_schema_path  # noqa: F401  — resolves ``from schema.*``
from src.employees.employees_exceptions import OwnerRowProtectedError
from src.employees.schema.employees_schema import (
    EmployeeResponse,
    EmployeeUpdateData,
    InviteStatus,
)
from src.employees.service.employees_update import EmployeesUpdate
from src.shared.column_guard import validate_mutable_columns


def _target(employee_type: EmployeeType, employee_id: UUID) -> EmployeeResponse:
    return EmployeeResponse(
        employee_id=employee_id,
        gym_id=uuid4(),
        employee_type=employee_type,
        first_name="Olivia",
        last_name="Owner",
        phone=None,
        email="olivia@example.com",
        employee_pic_url=None,
        employee_public_description=None,
        created_at=datetime.now(UTC),
        invite_status=InviteStatus.active,
    )


# ── _enforce_owner_rules ──────────────────────────────────────────


def test_owner_target_other_caller_raises() -> None:
    """The owner row may not be edited by a different employee (admin)."""
    employee_id = uuid4()
    with pytest.raises(OwnerRowProtectedError):
        EmployeesUpdate._enforce_owner_rules(
            _target(EmployeeType.owner, employee_id),
            employee_id,
            EmployeeUpdateData(first_name="Nope"),
            uuid4(),  # a DIFFERENT caller
        )


def test_owner_target_self_caller_role_change_raises() -> None:
    """Even the owner may not change the owner row's role."""
    employee_id = uuid4()
    with pytest.raises(OwnerRowProtectedError):
        EmployeesUpdate._enforce_owner_rules(
            _target(EmployeeType.owner, employee_id),
            employee_id,
            EmployeeUpdateData(employee_type=EmployeeType.admin),
            employee_id,  # the owner editing themselves
        )


def test_owner_target_self_caller_no_role_change_ok() -> None:
    """The owner editing their own non-role fields is allowed."""
    employee_id = uuid4()
    EmployeesUpdate._enforce_owner_rules(
        _target(EmployeeType.owner, employee_id),
        employee_id,
        EmployeeUpdateData(first_name="Olivia"),
        employee_id,
    )  # no raise


def test_non_owner_target_is_unrestricted() -> None:
    """A non-owner target (front_desk) has no owner-row restriction — an
    admin caller may even change its role."""
    employee_id = uuid4()
    EmployeesUpdate._enforce_owner_rules(
        _target(EmployeeType.front_desk, employee_id),
        employee_id,
        EmployeeUpdateData(employee_type=EmployeeType.admin),
        uuid4(),  # a different caller
    )  # no raise


# ── validate_mutable_columns ──────────────────────────────────────


def test_validate_mutable_columns_rejects_immutable() -> None:
    with pytest.raises(ValueError):
        validate_mutable_columns(GYM_EMPLOYEES, {"gym_id"})


def test_validate_mutable_columns_allows_mutable() -> None:
    validate_mutable_columns(
        GYM_EMPLOYEES, {"first_name", "email", "employee_type"}
    )  # no raise
