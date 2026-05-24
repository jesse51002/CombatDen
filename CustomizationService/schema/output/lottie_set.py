"""LottieSet — the lottie output group: every resolved lottie slot keyed by id.

The lottie module's per-slot outputs collected into one group on
``Output``. ``extra="ignore"`` matches ``FontSet`` / ``ImageSet``: this
group is read back from previously-produced ``output.yaml`` files and one
carrying since-removed keys must still validate. The wrapper exists so a
future run-wide lottie field is an additive change, never a breaking
reshape.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator

from schema.output.lottie_output import LottieOutput

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class LottieSet(BaseModel):
    """Every resolved lottie slot, keyed by snake_case slot id."""

    model_config = ConfigDict(extra="ignore")

    lotties: dict[str, LottieOutput]

    @field_validator("lotties")
    @classmethod
    def _slot_ids_snake_case(
        cls, v: dict[str, object]
    ) -> dict[str, object]:
        for slot_id in v:
            if not _ID_PATTERN.match(slot_id):
                raise ValueError(
                    f"lottie slot id {slot_id!r} must be snake_case "
                    "(lowercase, digits, underscores; must start with a "
                    "letter)"
                )
        return v
