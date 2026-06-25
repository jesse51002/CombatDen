"""Pydantic v2 schemas for the presets domain."""

from uuid import UUID

from pydantic import BaseModel


class PresetImportRequest(BaseModel):
    """Body for POST /api/v1/gyms/{gym_id}/presets/import."""

    video_gym_id: str


class PresetImportResponse(BaseModel):
    """Result returned after a successful preset import."""

    gym_id: UUID
    video_gym_id: str
    videos_imported: int
    classes_imported: int
    rewards_imported: int
    theme_design_id: str | None
