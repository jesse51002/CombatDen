"""Pydantic schemas for the waivers domain.

A waiver is a named document whose TEXT is versioned: each body edit publishes a
new immutable row in gym_waiver_versions, and a member signs a SPECIFIC version
(member_waiver_signatures). The catalog row (gym_waivers) holds identity + a
pointer to the current version; the wording lives on the versions table so the
exact signed text is preserved for the legal record.

This exposes catalog CRUD + version history + read-only signature tracking; the
signing-capture INSERT (`WaiversSignatures.record_signature`) is recorded
atomically by the authorized-payer link flow (memberships).
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, field_validator
from schema.member_waiver_signature import WaiverSignatureType

import src.shared.db_schema_path  # noqa: F401


class WaiverCreateRequest(BaseModel):
    """Create a waiver. Creating it also publishes version 1 from `body`."""

    gym_id: UUID
    name: str
    body: str

    @field_validator("name")
    @classmethod
    def _check_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("name cannot be empty")
        return v

    @field_validator("body")
    @classmethod
    def _check_body(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("body cannot be empty")
        return v


class WaiverUpdateData(BaseModel):
    """Mutable waiver fields. All optional — only send what changed.

    Supplying `body` publishes a NEW version (the existing versions are
    immutable); supplying `name` renames the catalog row in place.
    """

    name: str | None = None
    body: str | None = None

    @field_validator("name")
    @classmethod
    def _check_name(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("name cannot be empty")
        return v

    @field_validator("body")
    @classmethod
    def _check_body(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("body cannot be empty")
        return v


class WaiverUpdateRequest(BaseModel):
    """Rename a waiver and/or publish a new version of its text."""

    waiver_id: UUID
    gym_id: UUID
    data: WaiverUpdateData


class WaiverVersionResponse(BaseModel):
    """An immutable published version of a waiver's text."""

    version_id: UUID
    waiver_id: UUID
    gym_id: UUID
    version_number: int
    body: str
    content_hash: str
    created_at: datetime
    signature_count: int = 0


class WaiverResponse(BaseModel):
    """A waiver catalog entry. `current_version` is populated by the single-get;
    the list endpoint leaves it None (no body) and fills the summary counts."""

    waiver_id: UUID
    gym_id: UUID
    name: str
    current_version_id: UUID | None = None
    current_version_number: int | None = None
    current_version_signed_count: int = 0
    is_deleted: bool
    created_at: datetime
    updated_at: datetime
    current_version: WaiverVersionResponse | None = None


class WaiverSignatoryRow(BaseModel):
    """One row of a per-waiver signature roster: a member + their latest sign
    status for that waiver."""

    member_id: UUID
    first_name: str
    last_name: str
    signed: bool
    signed_at: datetime | None = None
    waiver_version_id: UUID | None = None
    version_number: int | None = None
    signed_current_version: bool = False


class MemberWaiverStatusRow(BaseModel):
    """One row of a member's waiver status: a gym waiver + this member's latest
    sign status for it (for the member-detail Waivers section)."""

    waiver_id: UUID
    name: str
    current_version_id: UUID | None = None
    current_version_number: int | None = None
    signed: bool
    signed_version_id: UUID | None = None
    signed_version_number: int | None = None
    signed_at: datetime | None = None
    signed_current_version: bool = False


class WaiverDefaultInfo(BaseModel):
    """A gym's default authorized-payer waiver + its current version — the
    target the payer signs when an authorized-payer link is created."""

    gym_id: UUID
    waiver_id: UUID
    version_id: UUID
    content_hash: str


# Re-exported so the signing-capture (link flow) and any consumer can reference
# the capture-method enum from this module.
__all__ = [
    "MemberWaiverStatusRow",
    "WaiverCreateRequest",
    "WaiverDefaultInfo",
    "WaiverResponse",
    "WaiverSignatoryRow",
    "WaiverSignatureType",
    "WaiverUpdateData",
    "WaiverUpdateRequest",
    "WaiverVersionResponse",
]
