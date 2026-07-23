"""Unit tests for the employees domain Pydantic schemas.

Covers the ``EmployeeCreateRequest`` / ``EmployeeUpdateData`` field
validators: owner-type rejection, blank-name rejection, email lowercasing,
name stripping, and the all-optional update model. Pure validation — no DB,
no TestClient.
"""

import pytest
from pydantic import ValidationError
from schema.gym_employee import EmployeeType

import src.shared.db_schema_path  # noqa: F401  — resolves ``from schema.*``
from src.employees.schema.employees_schema import (
    EmployeeCreateRequest,
    EmployeeUpdateData,
)

# ── EmployeeCreateRequest ─────────────────────────────────────────


def test_create_rejects_owner_type() -> None:
    """``employee_type='owner'`` is rejected — the owner row is seeded, not
    created through this endpoint."""
    with pytest.raises(ValidationError):
        EmployeeCreateRequest(
            employee_type=EmployeeType.owner,
            first_name="Ada",
            last_name="Lovelace",
            email="ada@example.com",
        )


def test_create_rejects_blank_first_name() -> None:
    """A whitespace-only name field is a validation error."""
    with pytest.raises(ValidationError):
        EmployeeCreateRequest(
            employee_type=EmployeeType.front_desk,
            first_name="   ",
            last_name="Lovelace",
            email="ada@example.com",
        )


def test_create_rejects_blank_last_name() -> None:
    with pytest.raises(ValidationError):
        EmployeeCreateRequest(
            employee_type=EmployeeType.front_desk,
            first_name="Ada",
            last_name="",
            email="ada@example.com",
        )


def test_create_lowercases_email_and_strips_names() -> None:
    """Email is lowercased (to match the stored lowercase email) and the
    name fields are stripped of surrounding whitespace."""
    req = EmployeeCreateRequest(
        employee_type=EmployeeType.trainer,
        first_name="  Ada  ",
        last_name="  Lovelace ",
        email="Ada.Lovelace@Example.COM",
    )
    assert req.email == "ada.lovelace@example.com"
    assert req.first_name == "Ada"
    assert req.last_name == "Lovelace"


# ── EmployeeUpdateData ────────────────────────────────────────────


def test_update_rejects_owner_type() -> None:
    """An employee may never be set to ``owner``."""
    with pytest.raises(ValidationError):
        EmployeeUpdateData(employee_type=EmployeeType.owner)


def test_update_rejects_blank_name() -> None:
    with pytest.raises(ValidationError):
        EmployeeUpdateData(first_name="  ")


def test_update_lowercases_email() -> None:
    data = EmployeeUpdateData(email="Foo@Bar.COM")
    assert data.email == "foo@bar.com"


def test_update_strips_name() -> None:
    data = EmployeeUpdateData(first_name="  Grace ")
    assert data.first_name == "Grace"


def test_update_all_none_is_valid() -> None:
    """An all-optional update with nothing set is valid — every field
    defaults to ``None`` ('leave unchanged')."""
    data = EmployeeUpdateData()
    assert data.model_dump(exclude_none=True) == {}


def test_update_non_owner_type_is_valid() -> None:
    """A non-owner role change validates cleanly."""
    data = EmployeeUpdateData(employee_type=EmployeeType.admin)
    assert data.employee_type is EmployeeType.admin
