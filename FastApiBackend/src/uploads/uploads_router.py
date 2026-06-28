"""API routes for the uploads domain."""

import logging
from typing import Annotated, Literal

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security
from src.uploads.service.uploads_s3_service import UploadsS3Service
from src.uploads.uploads_schema import ImageUploadResponse

logger = logging.getLogger(__name__)

uploads_router = APIRouter(
    prefix="/api/v1/uploads",
    tags=["uploads"],
)

MAX_IMAGE_SIZE_BYTES: int = 5 * 1024 * 1024  # 5 MB


@uploads_router.post(
    "/image",
    response_model=ImageUploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Upload an image to the CDN",
    description=(
        "Accepts a multipart image upload and a ``category`` form field "
        "(``reward`` or ``member``). Proxies the bytes to the private S3 "
        "bucket and returns the CloudFront CDN URL with a content-hash "
        "cache-buster. Requires a valid gym-employee JWT."
    ),
    responses={
        201: {"description": "Image uploaded; CDN URL returned"},
        400: {"description": "Not an image, or file exceeds 5 MB"},
        401: {"description": "Not authenticated"},
        500: {"description": "Upload failed"},
    },
)
@inject
async def upload_image(
    file: UploadFile,
    category: Annotated[Literal["reward", "member"], Form()],
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    uploads_service: UploadsS3Service = Depends(
        Provide[DependencyInjector.uploads_s3_service]
    ),
) -> ImageUploadResponse:
    """Upload an image; returns its CDN URL."""
    auth.get_current_user(credentials)

    content_type = file.content_type or ""
    if not content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only image/* files are accepted",
        )

    data = await file.read()
    if len(data) > MAX_IMAGE_SIZE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"File exceeds the "
                f"{MAX_IMAGE_SIZE_BYTES // (1024 * 1024)} MB size limit"
            ),
        )

    try:
        cdn_url = await uploads_service.upload_image(data, content_type, category)
        return ImageUploadResponse(url=cdn_url)
    except Exception:
        logger.error("Image upload failed: category=%s", category, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Image upload failed",
        ) from None
