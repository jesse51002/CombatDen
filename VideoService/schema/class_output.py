"""``ClassImage`` — one branded class card.

A gym's class cards live ON the gym (``Gym.classes`` in ``schema/gym.py``); this
is the per-card model they're a list of. ``extra="forbid"`` — a stray key is a
typo and should fail loudly.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class ClassImage(BaseModel):
    """One class card: name, a horizontal class image, a description, and the
    instructor (name + bio + headshot) — matching the mobile class screen."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1)  # display name, e.g. "Pad Work"
    image_url: str = Field(min_length=1)  # horizontal (landscape) class image
    description: str = Field(min_length=1)  # what the class is / what to expect
    instructor_name: str = Field(min_length=1)
    instructor_bio: str = Field(min_length=1)  # the instructor "details" blurb
    instructor_image_url: str = Field(min_length=1)  # instructor headshot URL
