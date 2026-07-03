from enum import StrEnum
from uuid import UUID

from . import SeedModel


class WaiverType(StrEnum):
    """Mirrors the Postgres ``waiver_type`` enum on ``gym_waivers``.

    ``payer_auth`` = the gym's one undeletable authorized-payer agreement
    (signed in the authorize-payer link flow, never plan-attachable).
    ``custom`` = a gym-authored document attachable to membership plans.
    Expandable — more special-purpose types may follow.
    """

    payer_auth = "payer_auth"
    custom = "custom"


class GymWaiverCreate(SeedModel):
    waiver_id: UUID
    gym_id: UUID
    name: str
    current_version_id: UUID | None = None
    is_deleted: bool = False
    # Required (no default): the caller must state the type explicitly —
    # a silent `custom` here could seed a gym without its protected
    # payer_auth agreement (or a deletable copy that bypasses
    # trg_protect_payer_auth_waiver).
    waiver_type: WaiverType
