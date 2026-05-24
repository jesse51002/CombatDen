"""The `class_output.yaml` contract: a company's four branded class cards.

Lives next to `videos_config.yaml` under `apps/<app_id>/`, keyed by the same
`app_id`. Replaces the mobile app's hardcoded class images with on-brand ones.
Authored by the `class-images` skill, so — like `videos_config.yaml` and unlike
the machine-written `videos_output.yaml` — both models are `extra="forbid"`:
a stray key is a typo and should fail loudly.

Always exactly four classes, each just a display name and a horizontal image URL.
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


class ClassOutput(BaseModel):
    """A company's four class cards. The whole writable surface."""

    model_config = ConfigDict(extra="forbid")

    company_name: str = Field(min_length=2)
    app_id: str = Field(min_length=1)
    # Always exactly four — the mobile app shows four class cards.
    classes: list[ClassImage] = Field(min_length=4, max_length=4)
