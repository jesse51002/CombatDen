"""The `gyms/<gym_id>.yaml` contract: one gym, with its three content surfaces.

A **gym** is the real entity. It has one or more `gym_type` disciplines, a chosen
`theme` (a ThemeService design id — the gym files ARE the theme→gym mapping, so
VideoService never reads ThemeService), and three content surfaces, each its own
sub-model:

- `videos` (:class:`GymVideos`) — what the gym wants surfaced/avoided
  (`specification`) plus the scan's curated ids into the shared pool
  (`good_video_ids` served, `rejected_video_ids` not). Approval is a per-gym
  verdict; the same pool video can be good for one gym and rejected by another.
- `classes` — the gym's branded class cards (the existing :class:`ClassImage`).
- `rewards` — the gym's reward cards (:class:`RewardCard`, a class card minus the
  instructor — rewards have no instructor).

`gym_type` is a **list** (a gym may span disciplines, e.g. a spin+strength studio
drawing from `[spin_strength, indoor_cycling]`). The theme→gym mapping is
separately 1:1. `videos` is always present (the spec is authored up front);
`classes`/`rewards` are None until authored. Everything is `extra="forbid"`.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from schema.class_output import ClassImage
from schema.gym_type import GymType

__all__ = ["Gym", "GymSpecifications", "GymVideos", "RewardCard", "ScanCost"]


class ScanCost(BaseModel):
    """One per-gym scan run's spend — appended to the gym's `scan_costs` array
    each time the gym is scanned, so the gym keeps its own scan-cost history (the
    global `cost_log.yaml` also records a SCAN entry for the whole run)."""

    model_config = ConfigDict(extra="forbid")

    at: datetime  # when this scan ran (UTC)
    usd: float = Field(ge=0)  # LLM spend for scanning this gym


class GymSpecifications(BaseModel):
    """What this gym wants surfaced and what it rejects — the scan's criteria.

    Two tiers: a long, context-rich pair the scan judges against
    (``videos_desc`` / ``avoid_desc``, required) and a short ~2-sentence summary
    for easy viewing (``short_videos_desc`` / ``short_avoid_desc``, display-only,
    not read by the scan). The short pair is optional for now and becomes
    required once every gym is backfilled.
    """

    model_config = ConfigDict(extra="forbid")

    # SHORT — ~2-sentence summary for easy viewing (approval gate, README). NOT
    # used by the scan. Optional for now; required after the Phase-2 backfill.
    short_videos_desc: str | None = Field(default=None, min_length=2)
    short_avoid_desc: str | None = Field(default=None, min_length=2)
    # LONG — the full, context-rich criteria the SCAN judges against (required).
    videos_desc: str = Field(min_length=2)  # prose: the kinds of videos worth surfacing
    avoid_desc: str = Field(min_length=2)  # prose: content this gym rejects


class GymVideos(BaseModel):
    """The gym's video surface: its scan criteria plus the curated feed (id-lists
    into the shared pool). `good_video_ids` is the only list ever served."""

    model_config = ConfigDict(extra="forbid")

    specification: GymSpecifications
    # The YouTube search queries that populate this gym's slice of the pool —
    # fed to the Apify search. Authored per gym (the gym owns its searches).
    queries: list[str] = Field(default_factory=list)
    # The scan verdict: pool video ids approved for this gym's feed. Empty until
    # the scan has run.
    good_video_ids: list[str] = Field(default_factory=list)
    # Pool video ids the scan rejected (kept for audit / re-scan avoidance). Never
    # served.
    rejected_video_ids: list[str] = Field(default_factory=list)
    # Append-only per-gym scan-cost history (one entry per scan run of this gym).
    scan_costs: list[ScanCost] = Field(default_factory=list)


class RewardCard(BaseModel):
    """One points-store reward, matching AppManagement's loyalty store
    (``LoyaltyReward``): a title, an image, what the member pays on top of points
    (``price_label``, e.g. "Free" / "30% off"), and the points cost."""

    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1)  # reward name, e.g. "Bring a friend"
    image_url: str = Field(min_length=1)  # horizontal (landscape) reward image
    price_label: str = Field(min_length=1)  # paid on top of points: "Free", "30% off"
    points_cost: int = Field(ge=0)  # points required to redeem


class Gym(BaseModel):
    """One gym: its discipline(s), chosen theme, and its videos/classes/rewards."""

    model_config = ConfigDict(extra="forbid")

    gym_id: str = Field(min_length=1)  # this gym's stable id (the YAML filename stem)
    # The discipline(s) this gym draws candidates from — its slice(s) of the pool.
    gym_type: list[GymType] = Field(min_length=1)
    theme: str = Field(min_length=1)  # chosen design id (ThemeService folder name)
    videos: GymVideos  # always present — the spec is authored up front
    # The gym's branded class cards (same shape as the legacy ClassOutput). None
    # until authored.
    classes: list[ClassImage] | None = None
    # The gym's reward cards. None until authored.
    rewards: list[RewardCard] | None = None
