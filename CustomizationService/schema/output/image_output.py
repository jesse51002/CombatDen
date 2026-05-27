"""ImageOutput — the resolved value for one image slot."""

from __future__ import annotations

from pydantic import ConfigDict, field_validator

from schema.complexity import Complexity
from schema.output.node_output import NodeOutput
from schema.primitives import AbsolutePath


class ImageOutput(NodeOutput):
    """One generated image: where it is, the prompt that made it, and the
    complexity tier that picked the generator's quality.

    ``complexity`` is optional: every fresh run sets it, but older or
    externally-produced ``output.yaml`` files predate it and must still
    validate. ``extra="ignore"`` (not the package-wide ``forbid``) is a
    deliberate exception: this model is read back from externally- or
    previously-produced ``output.yaml`` files that may carry now-removed
    keys (``adherent``, ``edited_prompt``, ``edited_reason``,
    ``dependency_usage``) — those are silently dropped, not rejected."""

    model_config = ConfigDict(extra="ignore")

    path: AbsolutePath
    # Content fingerprint of the delivered bytes — the API's cache-busting
    # ``?v=`` token. Stamped by the Writer at serialize time; empty on a
    # legacy ``output.yaml`` written before this field (URL stays unversioned).
    version: str = ""
    prompt: str
    complexity: Complexity | None = None

    @field_validator("prompt")
    @classmethod
    def _prompt_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ImageOutput.prompt must be non-empty")
        return v
