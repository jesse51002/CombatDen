"""The brief-agent endpoint: one conversational turn, and the accept path.

**One endpoint, both jobs.** A turn that carries ``accepted_brief`` commits it
and *then* runs the agent so it can acknowledge; a turn without one just
converses. Splitting them would put the save behind a second round trip and
let a client accept a brief without the conversation ever hearing about it.

**Stateless.** No session is stored here — the client holds the transcript and
posts it back each turn (see ``src/studio/schema/agent_turn.py``).

The plain form (``POST /briefs``) remains the non-agent path and needs no API
key; both commit through the same ``BriefService``.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, status
from pydantic import ValidationError

from src.studio.agent.brief_agent_service import brief_agent_service
from src.studio.schema.agent_turn import AgentTurnRequest, AgentTurnResponse

logger = logging.getLogger(__name__)

agent_router = APIRouter(prefix="/brief-agent", tags=["briefs"])


@agent_router.post(
    "",
    response_model=AgentTurnResponse,
    summary="One conversational turn with the brand-brief agent",
    responses={
        200: {
            "description": (
                "The agent's reply, a multiple-choice question, or a proposed "
                "brief — plus the transcript to send back next turn"
            )
        },
        422: {
            "description": (
                "The request is malformed, or an accepted brief cannot be "
                "committed (a blank field, or a design name with no sluggable "
                "characters)"
            )
        },
        500: {"description": "The agent failed to respond"},
        503: {"description": "No ANTHROPIC_API_KEY is configured"},
    },
)
async def brief_agent_turn(request: AgentTurnRequest) -> AgentTurnResponse:
    """Converse — or, when ``accepted_brief`` is set, commit and acknowledge.

    The commit is deterministic ``BriefService.commit``, the same call the
    plain form makes. It runs BEFORE the agent, so a brief is never reported
    saved because a model said so.
    """
    try:
        return await brief_agent_service().turn(request)
    except LookupError as exc:
        # The one unconfigured feature, not a broken app: everything else in
        # the studio still works without a key.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)
        ) from None
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=exc.errors(include_url=False, include_context=False),
        ) from None
    except ValueError as exc:
        # The un-sluggable design name. (ValidationError is a ValueError, so
        # it is caught above this.)
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("brief-agent turn failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The brief agent failed to respond.",
        ) from None
