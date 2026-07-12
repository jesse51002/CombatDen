"""API routes for the tasks domain (read-only polling endpoints).

Tasks are created by the operation endpoints that kick them off (e.g.
``PUT /member_memberships/price`` returns a task_id); these routes are how
the CRM polls progress.
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_schema import TaskResponse

logger = logging.getLogger(__name__)

tasks_router = APIRouter(
    prefix="/api/v1/tasks",
    tags=["tasks"],
)


# NOTE: the static /ongoing route is registered BEFORE /{task_id} so it is
# never captured as a path parameter.
@tasks_router.get(
    "/ongoing",
    response_model=list[TaskResponse],
    summary="List a gym's ongoing tasks",
    description=(
        "The gym's unfinished (pending/running) tasks with their items. "
        "Each item carries old_item_id/new_item_id so the memberships screen "
        "can badge any membership currently inside a task."
    ),
    responses={
        200: {"description": "Ongoing tasks (possibly empty)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_ongoing_tasks(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> list[TaskResponse]:
    """List the gym's unfinished tasks (the CRM's memberships-screen poll)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

    try:
        return await tasks_service.list_ongoing_tasks(gym_id)
    except Exception:
        logger.error(
            "Failed to list ongoing tasks for gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list ongoing tasks",
        ) from None


@tasks_router.get(
    "/{task_id}",
    response_model=TaskResponse,
    summary="Get one task",
    description="One task with its items — the polling target after a 202.",
    responses={
        200: {"description": "The task"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Task not found for this gym"},
    },
)
@inject
async def get_task(
    task_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> TaskResponse:
    """Get one task + items (gym-scoped)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

    try:
        task = await tasks_service.get_task(task_id, gym_id)
    except Exception:
        logger.error(
            "Failed to get task %s for gym_id=%s",
            task_id,
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get task",
        ) from None

    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Task not found: task_id={task_id}",
        )
    return task
