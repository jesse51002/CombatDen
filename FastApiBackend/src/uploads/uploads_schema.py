"""Pydantic schemas for the uploads domain."""

from pydantic import BaseModel


class ImageUploadResponse(BaseModel):
    """Response returned after a successful image upload."""

    url: str
