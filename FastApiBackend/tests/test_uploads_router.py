"""Unit tests for the uploads router (POST /api/v1/uploads/image).

Mocks at the same seam as the other router tests: ``auth_mock`` (the
``Auth`` double from ``tests/conftest.py``) for the staff-principal gate,
and ``app.container.uploads_s3_service`` overridden with a plain
``MagicMock`` so no real S3/boto3 call is ever made — mirrors the
``app.container.ranks_service.override(...)`` pattern in
``tests/test_ranks_router.py``.
"""

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException, status

import src.uploads.uploads_router as uploads_router_module
from src.main import app

UPLOAD_URL = "/api/v1/uploads/image"


@pytest.fixture
def uploads_service_mock():
    """Override the DI-wired ``UploadsS3Service`` with a mock for one test."""
    service = MagicMock()
    service.upload_image = AsyncMock(
        return_value="https://cdn.combatden.net/reward/fake.png?v=deadbeef"
    )
    app.container.uploads_s3_service.override(service)
    try:
        yield service
    finally:
        app.container.uploads_s3_service.reset_override()


# ─── auth gate ────────────────────────────────────────────────────────────


def test_upload_image_403_when_not_staff_principal(
    client, auth_headers, auth_mock, uploads_service_mock
):
    """A non-staff JWT is rejected by verify_staff_principal before the
    service is ever reached."""
    auth_mock.verify_staff_principal = AsyncMock(
        side_effect=HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized: gym staff only",
        )
    )

    response = client.post(
        UPLOAD_URL,
        files={"file": ("photo.png", b"fake-png-bytes", "image/png")},
        data={"category": "reward"},
        headers=auth_headers,
    )

    assert response.status_code == 403
    uploads_service_mock.upload_image.assert_not_called()


# ─── validation ───────────────────────────────────────────────────────────


def test_upload_image_400_when_not_an_image(
    client, auth_headers, uploads_service_mock
):
    """A non-image content type is rejected with 400 before the service call."""
    response = client.post(
        UPLOAD_URL,
        files={"file": ("doc.pdf", b"%PDF-1.4 fake", "application/pdf")},
        data={"category": "reward"},
        headers=auth_headers,
    )

    assert response.status_code == 400
    assert "image" in response.json()["detail"].lower()
    uploads_service_mock.upload_image.assert_not_called()


def test_upload_image_400_when_oversized(
    client, auth_headers, uploads_service_mock, monkeypatch
):
    """A file exceeding the size cap is rejected without calling the
    service. The 5 MB cap is monkeypatched down to 10 bytes so the test
    payload can stay tiny instead of allocating a real 5 MB body."""
    monkeypatch.setattr(uploads_router_module, "MAX_IMAGE_SIZE_BYTES", 10)

    oversized_payload = b"x" * 100  # well under 5 MB, well over the 10-byte cap

    response = client.post(
        UPLOAD_URL,
        files={"file": ("photo.png", oversized_payload, "image/png")},
        data={"category": "reward"},
        headers=auth_headers,
    )

    assert response.status_code == 400
    assert "size limit" in response.json()["detail"].lower()
    uploads_service_mock.upload_image.assert_not_called()


def test_upload_image_422_when_category_invalid(
    client, auth_headers, uploads_service_mock
):
    """category is a Literal["reward", "member", "class", "gym"] form field
    — an unrecognized value is a 422 validation error, not a 400."""
    response = client.post(
        UPLOAD_URL,
        files={"file": ("photo.png", b"tiny-bytes", "image/png")},
        data={"category": "not-a-real-category"},
        headers=auth_headers,
    )

    assert response.status_code == 422
    uploads_service_mock.upload_image.assert_not_called()


# ─── happy path ───────────────────────────────────────────────────────────


def test_upload_image_201_happy_path(client, auth_headers, uploads_service_mock):
    """A valid image upload returns 201 with the CDN URL and forwards the
    exact (bytes, content_type, category) to the service. category='class'
    is accepted (not just 'reward'/'member')."""
    cdn_url = "https://cdn.combatden.net/class/abc123.png?v=deadbeef"
    uploads_service_mock.upload_image.return_value = cdn_url
    payload = b"tiny-fake-png-bytes"

    response = client.post(
        UPLOAD_URL,
        files={"file": ("photo.png", payload, "image/png")},
        data={"category": "class"},
        headers=auth_headers,
    )

    assert response.status_code == 201, response.text
    assert response.json() == {"url": cdn_url}

    uploads_service_mock.upload_image.assert_called_once()
    sent_bytes, sent_content_type, sent_category = (
        uploads_service_mock.upload_image.call_args.args
    )
    assert sent_bytes == payload
    assert sent_content_type == "image/png"
    assert sent_category == "class"


def test_upload_image_201_happy_path_gym_category(
    client, auth_headers, uploads_service_mock
):
    """category='gym' is accepted — for gym logo uploads from the CRM."""
    cdn_url = "https://cdn.combatden.net/gym/abc123.png?v=deadbeef"
    uploads_service_mock.upload_image.return_value = cdn_url
    payload = b"tiny-fake-png-bytes"

    response = client.post(
        UPLOAD_URL,
        files={"file": ("logo.png", payload, "image/png")},
        data={"category": "gym"},
        headers=auth_headers,
    )

    assert response.status_code == 201, response.text
    assert response.json() == {"url": cdn_url}

    uploads_service_mock.upload_image.assert_called_once()
    sent_bytes, sent_content_type, sent_category = (
        uploads_service_mock.upload_image.call_args.args
    )
    assert sent_bytes == payload
    assert sent_content_type == "image/png"
    assert sent_category == "gym"
