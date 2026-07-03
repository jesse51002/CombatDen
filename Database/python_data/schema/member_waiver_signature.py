from enum import StrEnum
from uuid import UUID

from . import SeedModel


class WaiverSignatureType(StrEnum):
    """Mirror of the Postgres waiver_signature_type enum."""

    typed = "typed"


class MemberWaiverSignatureCreate(SeedModel):
    signature_id: UUID
    gym_id: UUID
    member_id: UUID
    waiver_id: UUID
    waiver_version_id: UUID
    signer_name: str
    signature_type: WaiverSignatureType = WaiverSignatureType.typed
    consent_acknowledged: bool
    ip_address: str | None = None
    user_agent: str | None = None
    rendered_body: str
    content_hash: str
    esign_disclosure_version: str = "esign-v1"
    operator_employee_id: UUID | None = None
