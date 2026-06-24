from uuid import UUID

from . import SeedModel


class GymWaiverCreate(SeedModel):
    waiver_id: UUID
    gym_id: UUID
    name: str
    current_version_id: UUID | None = None
    is_deleted: bool = False
    # Required (no default): this model only ever builds the gym's
    # undeletable default authorized-payer waiver, so the caller must
    # state `is_default` explicitly — a silent `False` here would create
    # a deletable waiver that bypasses trg_prevent_default_waiver_removal.
    is_default: bool
