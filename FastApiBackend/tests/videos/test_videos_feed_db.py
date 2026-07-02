"""Live-DB regression guard for the feed-page query's parameter typing.

The pure-logic tests in ``test_videos_logic.py`` mock the DB session, so they
never let Postgres PREPARE ``videos_load_feed_page.sql``. That blind spot let a
real bug ship: with ``video_type``/``big_group`` both NULL (the CRM "Your
videos" tab, ``GET /api/v1/gyms/{id}/videos?owner=true``) the nullable params
were only ever used in ``$N IS NULL`` / bare ``= 'literal'`` positions, so
Postgres could not infer their type at PREPARE and raised
``asyncpg.exceptions.AmbiguousParameterError: could not determine data type of
parameter $4`` — a 500 regardless of table data.

The fix wraps those binds in an explicit ``CAST(:param AS text)``. This test
executes the real query against the live DB across every nullable-param combo;
it fails loudly (prepare error) if the casts are ever dropped. It does NOT
assert on row content — the seeded gym may have no video feed rows — only that
the query prepares and executes and returns a ``(list, int)``.

Live-DB test (uses the session-scoped ``db_pool`` + seeded ``gym_id``
fixtures), so it runs in the integration pass, not the hermetic unit pass.
"""

from __future__ import annotations

from unittest.mock import MagicMock
from uuid import UUID

import pytest
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.shared.database import DirectDatabasePool
from src.videos.schema.videos_big_group import BigGroup
from src.videos.schema.videos_schema import GymVideoCard
from src.videos.service.video_feed_service import VideoFeedService

# (video_type, big_group, owner) — every nullable/branch combination the
# router can produce. The NULL/NULL owner case is the exact 500 reproduction.
_PARAM_CASES = [
    pytest.param(None, None, True, id="owner-no-filter (the original 500)"),
    pytest.param(None, None, False, id="latest-run-no-filter"),
    pytest.param(VideoGenre.educational, None, False, id="genre-filter"),
    pytest.param(None, BigGroup.EDUCATIONAL, False, id="big-group-educational"),
    pytest.param(
        None, BigGroup.ENTERTAINMENT, False, id="big-group-entertainment"
    ),
]


@pytest.mark.parametrize("video_type, big_group, owner", _PARAM_CASES)
async def test_load_feed_page_prepares_against_live_db(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    video_type: VideoGenre | None,
    big_group: BigGroup | None,
    owner: bool,
) -> None:
    """The real feed-page query prepares + executes for every param combo.

    Guards against ``AmbiguousParameterError`` returning if the explicit
    ``CAST(...)`` on the nullable genre/group params is ever removed.
    """
    service = VideoFeedService(db_pool=db_pool, youtube_client=MagicMock())

    cards, total = await service.load_feed_page(
        gym_id,
        owner=owner,
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
