"""The brief endpoint: validate the five fields and commit them to disk.

The plain (non-agent) path. A conversational Pydantic AI authoring agent is
a planned follow-up and deliberately isn't here — when it lands, its accept
path calls the same ``BriefService.commit``, so there is exactly one place
that decides what a valid brief is and where it goes.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, status
from pydantic import ValidationError

from src.studio.schema.brief_request import BriefCommitted, BriefRequest
from src.studio.service.brief_service import brief_service

logger = logging.getLogger(__name__)

brief_router = APIRouter(prefix="/briefs", tags=["briefs"])


@brief_router.post(
    "",
    response_model=BriefCommitted,
    status_code=status.HTTP_201_CREATED,
    summary="Validate a brand brief and save it",
    responses={
        201: {"description": "The brief was validated and written"},
        422: {"description": "A brief field is blank, or the name has no "
              "sluggable characters"},
    },
)
async def commit_brief(request: BriefRequest) -> BriefCommitted:
    """Write ``.studio/briefs/<slug>.yaml`` from the five brief fields.

    The brief contract is ``schema/customization.py`` — exactly
    ``design_direction.{name, short_desc, long_desc}`` and
    ``colors_direction.{description, mode}``. Blank values are rejected
    there, and that rejection surfaces here as a 422.

    Re-posting the same slug overwrites it: a brief is an editable input,
    not a produced artifact.
    """
    try:
        return await brief_service().commit(request)
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=exc.errors(include_url=False, include_context=False),
        ) from None
    except ValueError as exc:
        # The un-sluggable design name.
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from None
