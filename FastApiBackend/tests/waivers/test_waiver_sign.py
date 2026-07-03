"""Standalone waiver signing path (``WaiversSignatures.sign_waiver``).

Covers the version-lock (the echoed version must equal the waiver's current
version), the server-captured audit fields (ip / user-agent / operator / esign
disclosure), and the not-found / stale-version error paths, plus the request
schema's consent + signer-name validators.

Requires the legal-hardening migration (``20260702040000_waiver_signature_
legal_hardening``) to be applied — the signature INSERT writes the new columns
(``esign_disclosure_version`` / ``operator_employee_id``) and relies on the
NOT NULL ip/user-agent.
"""

import uuid

import pytest
from pydantic import ValidationError
from schema.esign_disclosure import ESIGN_DISCLOSURE_VERSION
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.waivers.schema.waivers_schema import (
    WaiverCreateRequest,
    WaiverSignatureType,
    WaiverSignRequest,
)
from src.waivers.service.waivers_service import WaiversService


async def _delete_waiver_rows(db_pool, waiver_id) -> None:
    """Remove a waiver + its versions + any signatures (FK-safe order)."""
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM member_waiver_signatures WHERE waiver_id = :w"),
            {"w": str(waiver_id)},
        )
        await session.execute(
            text("UPDATE gym_waivers SET current_version_id = NULL WHERE waiver_id = :w"),
            {"w": str(waiver_id)},
        )
        await session.execute(
            text("DELETE FROM gym_waiver_versions WHERE waiver_id = :w"),
            {"w": str(waiver_id)},
        )
        await session.execute(
            text("DELETE FROM gym_waivers WHERE waiver_id = :w"),
            {"w": str(waiver_id)},
        )
        await session.commit()


async def _an_employee_id(db_pool, gym_id) -> uuid.UUID:
    """Return any employee_id of the seeded gym (the witness/operator)."""
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT employee_id FROM gym_employees WHERE gym_id = :g LIMIT 1"),
            {"g": str(gym_id)},
        )
        return result.scalar_one()


async def _read_signature(db_pool, signature_id):
    """Read a recorded signature row back for assertions."""
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT * FROM member_waiver_signatures WHERE signature_id = :s"),
            {"s": str(signature_id)},
        )
        return result.mappings().one()


async def test_sign_current_version_records_audit_fields(db_pool, gym_id, created):
    """Signing the current version records the row + all audit fields."""
    svc = WaiversService(db_pool)
    member = await created.member(gym_id)
    operator_id = await _an_employee_id(db_pool, gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Liability", body="# body"),
    )
    try:
        v1 = waiver.current_version
        resp = await svc.sign_waiver(
            gym_id=gym_id,
            member_id=member.member_id,
            waiver_id=waiver.waiver_id,
            waiver_version_id=v1.version_id,
            signer_name="Jane Doe",
            consent_acknowledged=True,
            ip_address="203.0.113.7",
            user_agent="pytest-agent",
            operator_employee_id=operator_id,
        )
        assert resp.member_id == member.member_id
        assert resp.waiver_version_id == v1.version_id
        assert resp.signature_type == WaiverSignatureType.typed

        row = await _read_signature(db_pool, resp.signature_id)
        assert str(row["ip_address"]) == "203.0.113.7"
        assert row["user_agent"] == "pytest-agent"
        assert str(row["operator_employee_id"]) == str(operator_id)
        assert row["esign_disclosure_version"] == ESIGN_DISCLOSURE_VERSION
        # No placeholders → rendered text == template; hashes match the version.
        assert row["rendered_body"] == "# body"
        assert row["content_hash"] == v1.content_hash
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


async def test_sign_renders_placeholders(db_pool, gym_id, created):
    """A {{placeholder}} in the body is rendered into the frozen text."""
    svc = WaiversService(db_pool)
    member = await created.member(gym_id)
    operator_id = await _an_employee_id(db_pool, gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(
            gym_id=gym_id, name="Param", body="I, {{signer_name}}, agree.",
        ),
    )
    try:
        v1 = waiver.current_version
        resp = await svc.sign_waiver(
            gym_id=gym_id,
            member_id=member.member_id,
            waiver_id=waiver.waiver_id,
            waiver_version_id=v1.version_id,
            signer_name="Jane Doe",
            consent_acknowledged=True,
            ip_address="203.0.113.7",
            user_agent="pytest-agent",
            operator_employee_id=operator_id,
        )
        row = await _read_signature(db_pool, resp.signature_id)
        # signer_name placeholder is filled; the version template is untouched.
        assert row["rendered_body"] == "I, Jane Doe, agree."
        versions = await svc.list_versions(waiver.waiver_id, gym_id)
        assert versions[0].body == "I, {{signer_name}}, agree."
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


async def test_sign_stale_version_rejected(db_pool, gym_id, created):
    """Echoing a version that is not the current one is rejected (→ 409)."""
    svc = WaiversService(db_pool)
    member = await created.member(gym_id)
    operator_id = await _an_employee_id(db_pool, gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Stale", body="# body"),
    )
    try:
        with pytest.raises(ValueError, match="reload"):
            await svc.sign_waiver(
                gym_id=gym_id,
                member_id=member.member_id,
                waiver_id=waiver.waiver_id,
                waiver_version_id=uuid.uuid4(),  # not the current version
                signer_name="Jane Doe",
                consent_acknowledged=True,
                ip_address="203.0.113.7",
                user_agent="pytest-agent",
                operator_employee_id=operator_id,
            )
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


async def test_sign_archived_waiver_not_found(db_pool, gym_id, created):
    """Signing an archived (soft-deleted) waiver is treated as not found."""
    svc = WaiversService(db_pool)
    member = await created.member(gym_id)
    operator_id = await _an_employee_id(db_pool, gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Archived", body="# body"),
    )
    try:
        v1 = waiver.current_version
        await svc.delete_waiver(waiver.waiver_id, gym_id)
        with pytest.raises(ValueError, match="not found"):
            await svc.sign_waiver(
                gym_id=gym_id,
                member_id=member.member_id,
                waiver_id=waiver.waiver_id,
                waiver_version_id=v1.version_id,
                signer_name="Jane Doe",
                consent_acknowledged=True,
                ip_address="203.0.113.7",
                user_agent="pytest-agent",
                operator_employee_id=operator_id,
            )
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


async def test_sign_member_not_in_gym(db_pool, gym_id):
    """A member_id that is not in the gym fails the FK → not found."""
    svc = WaiversService(db_pool)
    operator_id = await _an_employee_id(db_pool, gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="NoMember", body="# body"),
    )
    try:
        v1 = waiver.current_version
        with pytest.raises(ValueError, match="not found"):
            await svc.sign_waiver(
                gym_id=gym_id,
                member_id=uuid.uuid4(),  # not a member of this gym
                waiver_id=waiver.waiver_id,
                waiver_version_id=v1.version_id,
                signer_name="Jane Doe",
                consent_acknowledged=True,
                ip_address="203.0.113.7",
                user_agent="pytest-agent",
                operator_employee_id=operator_id,
            )
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


def test_sign_request_rejects_false_consent():
    """A false consent is rejected at deserialization (Literal[True])."""
    with pytest.raises(ValidationError):
        WaiverSignRequest(
            gym_id=uuid.uuid4(),
            member_id=uuid.uuid4(),
            waiver_version_id=uuid.uuid4(),
            signer_name="Jane Doe",
            consent_acknowledged=False,
        )


def test_sign_request_rejects_blank_signer_name():
    """A blank signer name is rejected by the validator."""
    with pytest.raises(ValidationError):
        WaiverSignRequest(
            gym_id=uuid.uuid4(),
            member_id=uuid.uuid4(),
            waiver_version_id=uuid.uuid4(),
            signer_name="   ",
            consent_acknowledged=True,
        )


def test_render_tolerates_markdown_escaped_tokens() -> None:
    """A markdown serializer may store a token backslash-escaped
    (``\\{\\{member\\_name\\}\\}``) — it displays identically in the editor,
    so the renderer must fill it exactly like the clean form. Regression:
    live testing shipped bodies in this shape and nothing rendered."""
    from src.waivers.service.waivers_signatures import WaiversSignatures

    escaped = (
        r"I \{\{member\_name\}\} sign on \{\{date\}\} at \{\{gym\_name\}\}"
    )
    rendered = WaiversSignatures._render(
        escaped,
        {"member_name": "Jane Doe", "date": "2026-07-02", "gym_name": "Iron"},
    )
    assert rendered == "I Jane Doe sign on 2026-07-02 at Iron"

    # The clean form still renders; unknown tokens stay literal either way.
    assert (
        WaiversSignatures._render(
            "Hi {{member_name}}, {{nope}} stays", {"member_name": "Jo"}
        )
        == "Hi Jo, {{nope}} stays"
    )
