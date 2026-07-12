"""API routes for the uploads domain."""

import logging
from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security
from src.uploads.service.uploads_s3_service import UploadsS3Service
from src.uploads.uploads_schema import ImageUploadResponse, UploadCategory

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
        "(``reward``, ``member``, ``class``, ``gym``, ``rank``, or "
        "``membership``). Proxies the bytes to the private S3 "
        "bucket and returns the CloudFront CDN URL with a content-hash "
        "cache-buster. Requires a staff principal (owner/admin of at "
        "least one gym)."
    ),
    responses={
        201: {"description": "Image uploaded; CDN URL returned"},
        400: {"description": "Not an image, or file exceeds 5 MB"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not a gym staff principal"},
        500: {"description": "Upload failed"},
    },
)
@inject
async def upload_image(
    file: UploadFile,
    category: Annotated[UploadCategory, Form()],
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    uploads_service: UploadsS3Service = Depends(
        Provide[DependencyInjector.uploads_s3_service]
    ),
) -> ImageUploadResponse:
    """Upload an image; returns its CDN URL."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_staff_principal(user_payload)

    content_type = file.content_type or ""
    if not content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only image/* files are accepted",
        )

    size_error = HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=(
            f"File exceeds the "
            f"{MAX_IMAGE_SIZE_BYTES // (1024 * 1024)} MB size limit"
        ),
    )
    # Reject on the parsed part size BEFORE buffering the body into memory;
    # the post-read check below stays as the backstop for a missing size.
    if file.size is not None and file.size > MAX_IMAGE_SIZE_BYTES:
        raise size_error

    data = await file.read()
    if len(data) > MAX_IMAGE_SIZE_BYTES:
        raise size_error

    try:
        cdn_url = await uploads_service.upload_image(
            data, content_type, category.value
        )
        return ImageUploadResponse(url=cdn_url)
    except Exception:
        logger.error("Image upload failed: category=%s", category, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Image upload failed",
        ) from None
