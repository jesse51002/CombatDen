from uuid import UUID

from . import SeedModel


class MemberAuthorizedPayerCreate(SeedModel):
    """An authorization: payer_member_id may pay for member_id.

    Gated by a signed waiver (signature_id). created_at is DB-defaulted.
    """

    member_id: UUID
    payer_member_id: UUID
    gym_id: UUID
    signature_id: UUID
