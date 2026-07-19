"""Unit tests for the membership-plan schema image_url contract.

Pure Pydantic — no DB / Stripe. image_url is required on create, optional on
update, and surfaced on the response model.
"""

from uuid import uuid4

import pytest
from pydantic import ValidationError
from schema.membership_plan import PlanType

from src.plans.plans_schema import (
    MembershipPlanCreateRequest,
    MembershipPlanResponse,
    MembershipPlanUpdateData,
)

_IMG = "https://cdn.combatden.net/membership/presets/activity-03.jpg"


def test_create_requires_image_url():
    with pytest.raises(ValidationError):
        MembershipPlanCreateRequest(
            gym_id=uuid4(),
            plan_name="No Image",
            plan_type=PlanType.recurring,
            duration_amount=1,
            duration_unit="month",
            price=5000,
        )


def test_create_accepts_image_url():
    req = MembershipPlanCreateRequest(
        gym_id=uuid4(),
        plan_name="With Image",
        image_url=_IMG,
        plan_type=PlanType.recurring,
        duration_amount=1,
        duration_unit="month",
        price=5000,
    )
    assert req.image_url == _IMG


def test_update_image_url_optional_and_accepted():
    # Absent — defaults to None (only sends what changed).
    assert MembershipPlanUpdateData().image_url is None
    # Present — accepted as a mutable field.
    assert MembershipPlanUpdateData(image_url=_IMG).image_url == _IMG


def test_response_surfaces_image_url():
    resp = MembershipPlanResponse(
        plan_id=uuid4(),
        gym_id=uuid4(),
        plan_name="Resp",
        image_url=_IMG,
        plan_type=PlanType.recurring,
        is_public=True,
        created_at="2026-07-11T00:00:00Z",
    )
    assert resp.image_url == _IMG
