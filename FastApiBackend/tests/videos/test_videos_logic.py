"""Pure-logic unit tests for the videos domain (no DB / no Stripe).

Covers the read-path transforms that don't need the database: the genre→group
and discipline→parent maps (asserted TOTAL so a new enum value can't silently go
unmapped), the small null-safe helpers on ``ThemeShowcaseService``, and the
owner-add YouTube-id extractor.

Also covers the paginated feed service method (``load_feed_page``) with a
mocked DB session to assert that limit/offset/filter params are forwarded to SQL
and that total is extracted from the ``COUNT(*) OVER()`` column.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID

import pytest
from pydantic import ValidationError
from schema.video import VideoGenre

from src.presets.service.presets_template_service import PresetsTemplateService
from src.theme.service.theme_showcase_service import ThemeShowcaseService
from src.videos.schema.videos_big_group import EDUCATIONAL_GENRES, BigGroup, big_group_for
from src.videos.schema.videos_gym_type import GymType
from src.videos.schema.videos_parent_gym_type import ParentGymType, parent_of
from src.videos.schema.videos_schema import GymVideoCard
from src.videos.service.video_feed_service import VideoFeedService

# Feed-ranking knobs the mocked feed service is built with (values don't matter
# to the mock — only that they are forwarded to the SQL binds).
_BUMP_FRACTION = 0.10
_HALF_LIFE_DAYS = 7.0
_HALF_LIFE_SECONDS = _HALF_LIFE_DAYS * 86400


def test_big_group_for_is_total_over_genres():
    # Every genre must map to a group (no KeyError / missing case).
    for genre in VideoGenre:
        assert isinstance(big_group_for(genre), BigGroup)


def test_big_group_educational_vs_entertainment():
    assert big_group_for(VideoGenre.educational) is BigGroup.EDUCATIONAL
    assert big_group_for(VideoGenre.analysis) is BigGroup.EDUCATIONAL
    assert big_group_for(VideoGenre.entertainment) is BigGroup.ENTERTAINMENT
    assert big_group_for(VideoGenre.memes) is BigGroup.ENTERTAINMENT


def test_parent_of_is_total_over_disciplines():
    # Exhaustive over GymType: a new discipline must declare its parent bucket.
    for discipline in GymType:
        assert isinstance(parent_of(discipline), ParentGymType)


def test_instructor_name_null_safe():
    assert ThemeShowcaseService._instructor_name("Mary", "Jo") == "Mary Jo"
    assert ThemeShowcaseService._instructor_name("Mary", None) == "Mary"
    assert ThemeShowcaseService._instructor_name(None, "Jo") == "Jo"
    assert ThemeShowcaseService._instructor_name(None, None) is None


def test_as_list_tolerates_json_string_and_none():
    assert PresetsTemplateService._as_list(None) == []
    assert PresetsTemplateService._as_list('["a", "b"]') == ["a", "b"]
    assert PresetsTemplateService._as_list(["a"]) == ["a"]


# ── owner-add: YouTube id extraction ─────────────────────────────────

_VALID_ID = "dQw4w9WgXcQ"  # 11 chars, the standard YouTube id shape


@pytest.mark.parametrize(
    "url",
    [
        f"https://www.youtube.com/watch?v={_VALID_ID}",
        f"https://www.youtube.com/watch?v={_VALID_ID}&t=42s",
        f"https://m.youtube.com/watch?v={_VALID_ID}",
        f"https://youtu.be/{_VALID_ID}",
        f"https://youtu.be/{_VALID_ID}?si=abcd",
        f"https://www.youtube.com/embed/{_VALID_ID}",
        f"https://www.youtube.com/shorts/{_VALID_ID}",
        f"https://www.youtube.com/live/{_VALID_ID}",
        f"youtube.com/watch?v={_VALID_ID}",  # scheme-less
        _VALID_ID,  # a bare id
    ],
)
def test_extract_youtube_id_accepts_known_forms(url: str):
    assert VideoFeedService._extract_youtube_id(url) == _VALID_ID


@pytest.mark.parametrize(
    "url",
    [
        "",
        "   ",
        "https://vimeo.com/123456",
        "https://example.com/watch?v=" + _VALID_ID,  # right path, wrong host
        "https://www.youtube.com/watch?v=",  # no id
        "https://www.youtube.com/feed/subscriptions",  # no id segment
        "not a url at all",
        "https://youtu.be/short",  # too short to be an id
    ],
)
def test_extract_youtube_id_rejects_garbage(url: str):
    with pytest.raises(ValueError):
        VideoFeedService._extract_youtube_id(url)


# ── load_feed_page: paginated DB feed (mocked session) ───────────────

_GYM_ID = UUID("00000000-0000-0000-0000-000000000001")

_EDUCATIONAL_GENRE_VALUES = [g.value for g in EDUCATIONAL_GENRES]


def _make_feed_service(mock_rows: list[dict]) -> tuple[VideoFeedService, MagicMock]:
    """Build a VideoFeedService whose DB session returns the given rows."""
    mock_result = MagicMock()
    mock_result.mappings.return_value.all.return_value = mock_rows

    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(return_value=mock_result)

    @asynccontextmanager
    async def _session_ctx():
        yield mock_session

    mock_db = MagicMock()
    mock_db.session = _session_ctx

    svc = VideoFeedService(
        db_pool=mock_db,
        youtube_client=MagicMock(),
        profile_service=MagicMock(),
        bump_sigma_fraction=_BUMP_FRACTION,
        watch_penalty_half_life_days=_HALF_LIFE_DAYS,
    )
    return svc, mock_session


def _video_row(**overrides: object) -> dict:
    """A minimal valid pool-video row with a ``total`` column."""
    base = {
        "video_id": "vid1",
        "url": "https://www.youtube.com/watch?v=vid1",
        "title": "Test Video",
        "description": None,
        "thumbnail_url": "https://img.youtube.com/vi/vid1/hqdefault.jpg",
        "channel_name": "Test Channel",
        "channel_url": "https://www.youtube.com/channel/test",
        "channel_avatar_url": "",
        "view_count": 1000,
        "like_count": None,
        "duration_seconds": 120,
        "tag": None,
        "gym_type": None,
        "source_queries": None,
        "relevance_index": 0,
        "transcript_error": None,
        "transcript": None,
        "total": 1,
    }
    return {**base, **overrides}


async def test_load_feed_page_no_filter_returns_page_and_total() -> None:
    """No tag filter: video_type and filter_big_group are both None in params."""
    svc, mock_session = _make_feed_service([_video_row(total=5)])

    cards, total = await svc.load_feed_page(
        _GYM_ID,
        rejected=False,
        video_type=None,
        big_group=None,
        limit=10,
        offset=0,
    )

    assert total == 5
    assert len(cards) == 1

    params = mock_session.execute.call_args[0][1]
    assert params["video_type"] is None
    assert params["filter_big_group"] is None
    assert params["limit"] == 10
    assert params["offset"] == 0
    assert params["gym_id"] == str(_GYM_ID)
    assert params["educational_genres"] == _EDUCATIONAL_GENRE_VALUES
    # No member_id supplied → embedding + member_id bound NULL, rank knobs bound.
    assert params["member_embedding"] is None
    assert params["member_id"] is None
    assert params["bump_fraction"] == _BUMP_FRACTION
    assert params["half_life_seconds"] == _HALF_LIFE_SECONDS
    # The owner/source split is gone — one merged candidate set.
    assert "owner" not in params
    assert "source" not in params


async def test_load_feed_page_video_type_filter() -> None:
    """video_type passes its string value as :video_type param."""
    svc, mock_session = _make_feed_service([_video_row(tag="educational", total=3)])

    cards, total = await svc.load_feed_page(
        _GYM_ID,
        video_type=VideoGenre.educational,
        limit=20,
        offset=0,
    )

    assert total == 3
    params = mock_session.execute.call_args[0][1]
    assert params["video_type"] == VideoGenre.educational.value
    assert params["filter_big_group"] is None


async def test_load_feed_page_big_group_educational() -> None:
    """big_group=EDUCATIONAL passes filter_big_group='educational' to SQL."""
    svc, mock_session = _make_feed_service([_video_row(tag="educational", total=2)])

    cards, total = await svc.load_feed_page(
        _GYM_ID,
        big_group=BigGroup.EDUCATIONAL,
        limit=20,
        offset=0,
    )

    assert total == 2
    params = mock_session.execute.call_args[0][1]
    assert params["video_type"] is None
    assert params["filter_big_group"] == BigGroup.EDUCATIONAL.value


async def test_load_feed_page_big_group_entertainment() -> None:
    """big_group=ENTERTAINMENT passes filter_big_group='entertainment' to SQL."""
    svc, mock_session = _make_feed_service([_video_row(tag="entertainment", total=7)])

    cards, total = await svc.load_feed_page(
        _GYM_ID,
        big_group=BigGroup.ENTERTAINMENT,
        limit=5,
        offset=10,
    )

    assert total == 7
    params = mock_session.execute.call_args[0][1]
    assert params["filter_big_group"] == BigGroup.ENTERTAINMENT.value
    assert params["limit"] == 5
    assert params["offset"] == 10


async def test_load_feed_page_empty_result_returns_zero_total() -> None:
    """When DB returns no rows (no matches), return ([], 0)."""
    svc, _ = _make_feed_service([])

    cards, total = await svc.load_feed_page(
        _GYM_ID,
        limit=10,
        offset=0,
    )

    assert cards == []
    assert total == 0


async def test_load_feed_page_rejected_maps_scan_status_no_owner_param() -> None:
    """rejected=True maps scan_status='rejected'; there is NO owner/source param
    (one merged candidate set), and the rank binds are always present."""
    svc, mock_session = _make_feed_service([_video_row(total=1)])

    await svc.load_feed_page(
        _GYM_ID,
        rejected=True,
        member_id=None,
        limit=10,
        offset=0,
    )

    params = mock_session.execute.call_args[0][1]
    assert params["scan_status"] == "rejected"
    assert "owner" not in params
    assert "source" not in params
    assert params["member_embedding"] is None
    assert params["member_id"] is None
    assert params["bump_fraction"] == _BUMP_FRACTION
    assert params["half_life_seconds"] == _HALF_LIFE_SECONDS


async def test_load_feed_page_binds_member_embedding_when_member_has_profile() -> None:
    """A member with a built embedding binds it + the member_id for the penalty.

    The embedding is read through the GUARDED ``verify_and_load_embedding`` (the
    membership guard + embedding read in one), called with the path gym_id."""
    member_id = UUID("00000000-0000-0000-0000-0000000000aa")
    svc, mock_session = _make_feed_service([_video_row(total=1)])
    # Give the (mocked) profile service a built embedding for this member.
    svc._profiles.verify_and_load_embedding = AsyncMock(return_value="[0.1,0.2]")

    await svc.load_feed_page(_GYM_ID, member_id=member_id, limit=10, offset=0)

    svc._profiles.verify_and_load_embedding.assert_awaited_once_with(
        member_id, _GYM_ID
    )
    params = mock_session.execute.call_args[0][1]
    assert params["member_embedding"] == "[0.1,0.2]"
    assert params["member_id"] == str(member_id)


async def test_load_owner_videos_exposes_enriched_flag() -> None:
    """The ungated owner listing hydrates cards, forwards gym/limit/offset (no
    owner/scan_status param), and a row can carry enriched=False + owner_added."""
    row = _video_row(owner_added=True, enriched=False, total=1)
    svc, mock_session = _make_feed_service([row])

    cards, total = await svc.load_owner_videos(_GYM_ID, limit=15, offset=5)

    assert total == 1
    assert len(cards) == 1
    assert cards[0].enriched is False
    assert cards[0].owner_added is True
    params = mock_session.execute.call_args[0][1]
    assert params["gym_id"] == str(_GYM_ID)
    assert params["limit"] == 15
    assert params["offset"] == 5
    assert "owner" not in params
    assert "scan_status" not in params


# ── load_feed_preview: windowed per-genre sections (mocked session) ──


async def test_load_feed_preview_forwards_params_and_builds_sections() -> None:
    """Forwards gym/scan_status/per_tag (no member/rank binds) and groups the
    SQL's ordered rows into one section per genre in first-appearance order."""
    rows = [
        _video_row(video_id="a", tag="educational", relevance_index=0),
        _video_row(video_id="b", tag="educational", relevance_index=1),
        _video_row(video_id="c", tag="memes", relevance_index=2),
    ]
    svc, mock_session = _make_feed_service(rows)

    sections = await svc.load_feed_preview(_GYM_ID, per_tag=10, rejected=False)

    params = mock_session.execute.call_args[0][1]
    assert params["gym_id"] == str(_GYM_ID)
    assert params["scan_status"] == "accepted"
    assert params["per_tag"] == 10
    assert "member_id" not in params  # preview never personalizes
    assert [s.tag for s in sections] == [VideoGenre.educational, VideoGenre.memes]
    assert [v.video_id for v in sections[0].videos] == ["a", "b"]
    assert [v.video_id for v in sections[1].videos] == ["c"]


async def test_load_feed_preview_rejected_maps_scan_status() -> None:
    svc, mock_session = _make_feed_service([_video_row(tag="educational")])

    await svc.load_feed_preview(_GYM_ID, per_tag=5, rejected=True)

    params = mock_session.execute.call_args[0][1]
    assert params["scan_status"] == "rejected"
    assert params["per_tag"] == 5


def test_build_preview_sections_skips_untagged_and_invalid_rows() -> None:
    """Untagged videos form no section; a row that fails GymVideoCard validation
    (ge=0 relevance) is skipped without breaking the preview."""
    good = _video_row(video_id="g", tag="educational")
    untagged = _video_row(video_id="u", tag=None)
    invalid = _video_row(video_id="x", tag="educational", relevance_index=-1)

    sections = VideoFeedService._build_preview_sections([good, untagged, invalid])

    assert len(sections) == 1
    assert sections[0].tag == VideoGenre.educational
    assert [v.video_id for v in sections[0].videos] == ["g"]


def test_gym_video_card_requires_video_id() -> None:
    """video_id is a required field now; a card without it fails validation and
    one with it (defaulting owner_added/enriched) validates."""
    base = {
        "url": "https://youtu.be/x",
        "title": "T",
        "thumbnail_url": "https://img/x.jpg",
        "channel_name": "C",
        "channel_url": "https://c",
        "channel_avatar_url": "",
        "relevance_index": 0,
    }
    with pytest.raises(ValidationError):
        GymVideoCard(**base)

    card = GymVideoCard(video_id="vid1", **base)
    assert card.video_id == "vid1"
    assert card.owner_added is False  # default
    assert card.enriched is True  # default


async def test_load_feed_page_invalid_row_skipped() -> None:
    """A row that fails GymVideoCard validation is silently skipped."""
    bad_row = _video_row(relevance_index=-1, total=2)  # ge=0 constraint fails
    good_row = _video_row(video_id="vid2", total=2)
    svc, _ = _make_feed_service([bad_row, good_row])

    cards, total = await svc.load_feed_page(_GYM_ID, limit=10, offset=0)

    assert total == 2
    assert len(cards) == 1
