"""Pydantic schemas for the CRM members list endpoint."""

from datetime import date
from enum import StrEnum
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field


class MembersListView(StrEnum):
    """Available views for the members list screen."""

    all = "all"
    trial = "trial"
    frozen = "frozen"
    overdue = "overdue"


class CrmMemberStatus(StrEnum):
    """Computed membership status for CRM display.

    Extends DB statuses with derived values like trial,
    overdue, dormant, and no_membership.

    ``dormant`` is a member-level status: they hold only short
    (trial / one_time) live packs and have gone quiet for longer than
    the gym's dormancy window. Without it those members display as
    ``active`` / ``trial``, which reads as "in progress" for someone who
    bought a pack and vanished. Its derivation and badge precedence live
    in ``src/members/service/members_status_mapping.py``.
    """

    active = "active"
    trial = "trial"
    frozen = "frozen"
    cancelled = "cancelled"
    ended = "ended"
    overdue = "overdue"
    dormant = "dormant"
    no_membership = "no_membership"


class DateRangeFilter(BaseModel):
    """Filter by date range (membership start date).

    Attributes:
        start_date: Start of the date range.
        end_date: End of the date range.
    """

    start_date: date | None = None
    end_date: date | None = None


class MembersListFilters(BaseModel):
    """All filters for the members list.

    Each dimension narrows the result independently (they are
    AND-combined); multiple values within a dimension widen it
    (membership_status, plan_ids, and rank_ids are OR-combined
    internally).

    Attributes:
        membership_status: Statuses to include.
        plan_ids: Membership plans to include — members with a
            LIVE (active or frozen) membership on any of these
            plans; cancelled/ended memberships do not match.
        rank_ids: Ranks to include — members whose current rank
            (``members.current_rank_id``) is any of these.
        date_range: Optional date range filter.
        name: Optional name search string.
    """

    membership_status: list[CrmMemberStatus] = []
    plan_ids: list[UUID] = []
    rank_ids: list[UUID] = []
    date_range: DateRangeFilter | None = None
    name: str | None = None


class CrmMembersListRequest(BaseModel):
    """Request body for the CRM members list endpoint.

    Attributes:
        gym_id: The gym to list members for.
        view: The view to show (decides the row shape). The
            view and the filters are independent — the server
            applies both as given and does not reconcile one
            against the other.
        filters: Active filters from the frontend.
        start_index: Pagination offset.
        count: Number of rows to fetch per page.
    """

    gym_id: UUID
    view: MembersListView
    filters: MembersListFilters = MembersListFilters()
    start_index: int = 0
    count: int = 25


# -- Row models (one per view, discriminated on "view") --


class BaseRow(BaseModel):
    """Fields shared by every view row."""

    member_id: UUID
    name: str
    avatar_url: str | None = None


class AllViewRow(BaseRow):
    """Row for the All view.

    Includes contact, membership badge, and last class.
    """

    view: Literal[MembersListView.all] = MembersListView.all
    email: str | None = None
    membership_status: CrmMemberStatus
    membership_text: str
    days_since_last_class: int | None = None


class TrialViewRow(BaseRow):
    """Row for the Trial view.

    Includes trial period dates and days remaining.
    """

    view: Literal[MembersListView.trial] = MembersListView.trial
    days_remaining: int
    start_date: str
    end_date: str


class FrozenViewRow(BaseRow):
    """Row for the Frozen view.

    Includes freeze period and membership price.
    """

    view: Literal[MembersListView.frozen] = MembersListView.frozen
    freeze_start: str
    days_until_unfrozen: int
    freeze_end: str
    price: str


class OverdueViewRow(BaseRow):
    """Row for the Overdue view.

    Shows members with overdue payments.
    """

    view: Literal[MembersListView.overdue] = MembersListView.overdue
    email: str | None = None
    phone: str | None = None
    membership_text: str
    days_late: int


MembersListRow = Annotated[
    AllViewRow | TrialViewRow | FrozenViewRow | OverdueViewRow,
    Field(discriminator="view"),
]


# -- Response models --


class MembersListTotalCounts(BaseModel):
    """Aggregate member counts across the full dataset.

    Always reflects totals regardless of active view or filters.

    These are independent tallies, not a partition: a member can be
    counted under more than one heading (an overdue member is also
    counted as active, and a dormant one is also counted as trial when
    their pack is a trial). ``dormant`` follows that existing shape, and
    counts the dormancy RULE — a dormant member whose membership is
    frozen or past due is counted here even though a higher-precedence
    badge claims their row in the list.
    """

    active: int
    trial: int
    frozen: int
    overdue: int
    dormant: int


class CrmMembersListResponse(BaseModel):
    """Response for the CRM members list endpoint.

    Attributes:
        view: The resolved view (echoed from request).
        filters: The applied filters (echoed from request).
        data: Pre-sorted, pre-filtered, pre-formatted rows.
    """

    view: MembersListView
    filters: MembersListFilters
    data: list[MembersListRow]
