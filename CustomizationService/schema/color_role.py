"""ColorRole — the validation-only role a colour slot may declare.

A slot tags itself ``background`` or ``text`` purely so the deterministic
post-generation check knows which resolved colours to contrast-test and
sanity-bound. It is never sent to the LLM (the prompt keeps inferring role
from the slot description). Most slots (primary, accent, …) carry no role.
"""

from __future__ import annotations

import enum


class ColorRole(str, enum.Enum):
    """The two structural roles the contrast check needs."""

    BACKGROUND = "background"
    TEXT = "text"
