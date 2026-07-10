"""Live-DB regression guard for the unified feed-page query's parameter typing.

The pure-logic tests in ``test_videos_logic.py`` mock the DB session, so they
never let Postgres PREPARE ``videos_load_feed_page.sql``. That blind spot let a
real bug ship: with ``video_type``/``big_group`` both NULL the nullable params
were only ever used in ``$N IS NULL`` / bare ``= 'literal'`` positions, so
Postgres could not infer their type at PREPARE and raised
``asyncpg.exceptions.AmbiguousParameterError: could not determine data type of
parameter $4`` — a 500 regardless of table data.

The fix wraps those binds in an explicit ``CAST(...)``. The unified query adds
more nullable binds — ``:member_embedding`` (used both ``CAST(... AS text)`` and
``CAST(... AS vector)``), ``:member_id``, and the ``:bump_fraction`` /
``:half_life_seconds`` rank knobs — all cast, so this test now also guards those.
It executes the real query against the live DB across every nullable-param combo
(with NO member_id, so no ``members.video_profile_*`` read); it fails loudly
(prepare error) if the casts are ever dropped. It does NOT assert on row content
— the seeded gym may have no enriched feed rows — only that the query prepares
and executes and returns a ``(list, int)``.

The unified feed INNER JOINs ``video_rag``, so this test needs the video-worker
RAG migration's ``video_rag`` + ``member_video_recs`` tables applied on the
shared local DB; until then it fails at the query (relation missing) — the
expected "pending migration apply" state, not a code fault.

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
from src.videos.schema.videos_schema import GymFeedSection, GymVideoCard
from src.videos.service.video_feed_service import VideoFeedService

# (video_type, big_group) — every nullable/branch combination the router can
# produce. The NULL/NULL case is the original AmbiguousParameterError repro.
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
    """The real unified feed-page query prepares + executes for every param combo.

    Guards against ``AmbiguousParameterError`` returning if the explicit
    ``CAST(...)`` on any nullable param (genre/group/embedding/member_id/rank
    knobs) is ever removed.
    """
    service = VideoFeedService(
        db_pool=db_pool,
        youtube_client=MagicMock(),
        profile_service=MagicMock(),
        bump_sigma_fraction=0.10,
        watch_penalty_half_life_days=7.0,
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
    """The windowed per-genre preview query prepares + executes on the live DB.

    The mocked logic tests never let Postgres PREPARE
    ``videos_load_feed_preview.sql`` (the ROW_NUMBER / FIRST_VALUE window + the
    injected shared ``{candidate_source}`` core), so this executes it for real to
    catch a broken CTE/window or a param-typing regression. It asserts only the
    shape (list of ``GymFeedSection``), not row content — the seeded gym may have
    no enriched feed rows."""
    service = VideoFeedService(
        db_pool=db_pool,
        youtube_client=MagicMock(),
        profile_service=MagicMock(),
        bump_sigma_fraction=0.10,
        watch_penalty_half_life_days=7.0,
    )

    sections = await service.load_feed_preview(
        gym_id, per_tag=10, rejected=rejected
    )

    assert isinstance(sections, list)
    assert all(isinstance(s, GymFeedSection) for s in sections)
