"""Pydantic schemas for the waivers domain.

A waiver is a named document whose TEXT is versioned: each body edit publishes a
new immutable row in gym_waiver_versions, and a member signs a SPECIFIC version
(member_waiver_signatures). The catalog row (gym_waivers) holds identity + a
pointer to the current version; the wording lives on the versions table so the
exact signed text is preserved for the legal record.

This exposes catalog CRUD + version history + signature tracking + the signing
request/response (`WaiverSignRequest` / `WaiverSignatureResponse`) for the
standalone signing endpoint — the one path that records a signature
(`WaiversSignatures.sign_waiver`).
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, field_validator
from schema.gym_waiver import WaiverType
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

    Supplying `body` persists a text edit (in place while the current version
    is unsigned, else a NEW version); supplying `name` renames the catalog row
    in place. `requires_resign` marks whether prior signers must re-sign
    before their next purchase / check-in (False = a minor edit that should
    NOT re-block them): with a `body` it is stamped on the resulting current
    version (a fork defaults to True when omitted); WITHOUT a `body` it flips
    the flag on the CURRENT version in place — the mistake-correction toggle.
    None = leave the flag untouched.
    """

    name: str | None = None
    body: str | None = None
    requires_resign: bool | None = None

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
    """A published version of a waiver's text (body immutable once signed).

    ``requires_resign``: whether this version, once it is the highest such
    version, re-blocks prior signers (the re-sign floor). Correctable on the
    CURRENT version via the update endpoint's flag-only path."""

    version_id: UUID
    waiver_id: UUID
    gym_id: UUID
    version_number: int
    body: str
    content_hash: str
    requires_resign: bool = True
    created_at: datetime
    signature_count: int = 0


class WaiverResponse(BaseModel):
    """A waiver catalog entry. `current_version` is populated by the single-get;
    the list endpoint leaves it None (no body) and fills the summary counts."""

    waiver_id: UUID
    gym_id: UUID
    name: str
    # payer_auth = the gym's one protected authorized-payer agreement
    # (never plan-attachable); custom = a normal gym-authored waiver.
    waiver_type: WaiverType
    current_version_id: UUID | None = None
    current_version_number: int | None = None
    current_version_signed_count: int = 0
    # DISTINCT members who signed ANY version — the catalog's headline
    # "N signed" (a re-signer counts once).
    total_signed_count: int = 0
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
    """One row of a member's waiver status (the member-detail Waivers
    section): the UNION of the waivers they must sign and the waivers they
    have ever signed — a signature stays visible after the waiver stops
    being required or is archived (the legal record).

    ``meets_floor`` is the compliance verdict (latest signed version >= the
    waiver's ``requires_resign`` floor — the same rule as the purchase +
    check-in gates); ``signed and not meets_floor`` = needs re-signing."""

    waiver_id: UUID
    name: str
    waiver_type: WaiverType
    is_deleted: bool = False
    required: bool = False
    current_version_id: UUID | None = None
    current_version_number: int | None = None
    signed: bool
    signed_version_id: UUID | None = None
    signed_version_number: int | None = None
    signed_at: datetime | None = None
    signed_current_version: bool = False
    meets_floor: bool = False


class WaiverPayerAuthInfo(BaseModel):
    """A gym's default authorized-payer waiver + its current version — the
    target the payer signs when an authorized-payer link is created."""

    gym_id: UUID
    waiver_id: UUID
    version_id: UUID
    content_hash: str


class AuthorizedPayerWaiverResponse(BaseModel):
    """The gym's default authorized-payer waiver a payer must sign to be
    authorized for a member — identity plus the current version's body for
    display in the front-desk sign dialog. The link flow records the signature
    against this same current version internally, so the UI only echoes back
    the signer's name + consent (not the version id)."""

    waiver_id: UUID
    version_id: UUID
    name: str
    body: str


class WaiverSignRequest(BaseModel):
    """Record one member's signature on a waiver (standalone signing endpoint).

    The ``waiver_id`` is the path parameter; this body carries the rest. The
    client ECHOES the ``waiver_version_id`` it displayed so the backend can
    version-lock on it (reject if the gym published a newer version meanwhile),
    closing the read-then-sign race. The audit fields (ip / user-agent /
    operator / esign disclosure version) are captured server-side, never sent by
    the client.
    """

    gym_id: UUID
    member_id: UUID
    waiver_version_id: UUID
    signer_name: str
    consent_acknowledged: Literal[True]

    @field_validator("signer_name")
    @classmethod
    def _check_signer_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("signer_name cannot be empty")
        return v


class WaiverSignatureResponse(BaseModel):
    """A recorded e-signature row (the standalone signing endpoint's result)."""

    signature_id: UUID
    waiver_id: UUID
    waiver_version_id: UUID
    member_id: UUID
    gym_id: UUID
    signed_at: datetime
    signer_name: str
    signature_type: WaiverSignatureType


# Re-exported so the signing-capture (link flow) and any consumer can reference
# the capture-method enum from this module.
__all__ = [
    "AuthorizedPayerWaiverResponse",
    "MemberWaiverStatusRow",
    "WaiverCreateRequest",
    "WaiverPayerAuthInfo",
    "WaiverResponse",
    "WaiverSignRequest",
    "WaiverSignatoryRow",
    "WaiverSignatureResponse",
    "WaiverSignatureType",
    "WaiverUpdateData",
    "WaiverUpdateRequest",
    "WaiverVersionResponse",
]
