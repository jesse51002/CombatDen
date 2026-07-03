"""Pydantic schemas for the uploads domain."""

from enum import StrEnum

from pydantic import BaseModel


class UploadCategory(StrEnum):
    """What an uploaded image is for — doubles as the S3 key prefix.

    API-only value set (no DB column mirrors it); the single source of
    truth for the categories the router accepts and the service prefixes
    keys with.
    """

    reward = "reward"
    member = "member"
    class_ = "class"
    gym = "gym"


class ImageUploadResponse(BaseModel):
    """Response returned after a successful image upload."""

    url: str
