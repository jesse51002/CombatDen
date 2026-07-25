"""Live-DB regression guard for the feed queries' parameter typing.

The logic tests mock the DB session, so they never let Postgres PREPARE the
SQL — and every nullable bind here (``video_type`` / ``big_group`` /
``member_embedding`` / ``member_id`` / the rank knobs) needs an explicit
``CAST(...)``. Without one, a param used only in ``$N IS NULL`` or
``= 'literal'`` positions has no inferable type and the query dies at PREPARE
with ``AmbiguousParameterError`` — a 500 regardless of table data.

So these execute the real queries across every param combo and assert only the
SHAPE, never row content: parameter typing is a property of the query, so the
guard has to stay honest whatever the seeded gym's feed happens to hold.
"""

from __future__ import annotations

from unittest.mock import MagicMock
from uuid import UUID

import pytest
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.shared.database import DirectDatabasePool
from src.videos.schema.videos_big_group import BigGroup
from src.videos.schema.videos_schema import GymFeedSection, GymVideoCard
from src.videos.service.video_feed_service import VideoFeedService

# Every nullable/branch combination the router can produce; NULL/NULL is the
# AmbiguousParameterError repro.
_PARAM_CASES = [
    pytest.param(None, None, id="no-filter (the original 500)"),
    pytest.param(VideoGenre.educational, None, id="genre-filter"),
    pytest.param(None, BigGroup.EDUCATIONAL, id="big-group-educational"),
    pytest.param(None, BigGroup.ENTERTAINMENT, id="big-group-entertainment"),
]


@pytest.mark.parametrize("video_type, big_group", _PARAM_CASES)
async def test_load_feed_page_prepares_against_live_db(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    video_type: VideoGenre | None,
    big_group: BigGroup | None,
) -> None:
    """``videos_load_feed_page.sql`` prepares + executes for every param combo —
    it fails loudly if any nullable param's ``CAST(...)`` is ever dropped."""
    service = VideoFeedService(
        db_pool=db_pool,
        youtube_client=MagicMock(),
        profile_service=MagicMock(),
        bump_sigma_fraction=0.10,
        served_penalty_half_life_days=7.0,
    )

    cards, total = await service.load_feed_page(
        gym_id,
        rejected=False,
        video_type=video_type,
        big_group=big_group,
        limit=10,
        offset=0,
    )

    assert isinstance(cards, list)
    assert all(isinstance(c, GymVideoCard) for c in cards)
    assert isinstance(total, int)
    assert total >= 0


@pytest.mark.parametrize("rejected", [False, True])
async def test_load_feed_preview_prepares_against_live_db(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    rejected: bool,
) -> None:
    """``videos_load_feed_preview.sql`` prepares + executes on the live DB —
    catching a broken window/CTE or a param-typing regression in the
    ROW_NUMBER query and its injected shared ``{candidate_source}`` core."""
    service = VideoFeedService(
        db_pool=db_pool,
        youtube_client=MagicMock(),
        profile_service=MagicMock(),
        bump_sigma_fraction=0.10,
        served_penalty_half_life_days=7.0,
    )

    sections = await service.load_feed_preview(
        gym_id, per_tag=10, rejected=rejected
    )

    assert isinstance(sections, list)
    assert all(isinstance(s, GymFeedSection) for s in sections)
