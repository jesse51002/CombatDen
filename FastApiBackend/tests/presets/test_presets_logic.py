"""Pure-logic unit tests for the presets domain (no DB / no Stripe).

The instructor name-split is the one transform with edge cases worth pinning:
the import must always produce a non-empty first AND last name so the
``gym_employees`` NOT NULL / non-empty CHECK constraints are satisfied.

Also covers ``PresetsTemplateService.load_template_feed_page`` with a mocked
DB session to assert that limit/offset/filter params are forwarded to SQL and
that total is extracted from the ``COUNT(*) OVER()`` column.

The class-history/attendance/sign-up seeding itself (``_seed_history_and_
attendance`` and friends) is DB-session-driven and mostly has no unit
coverage here (mirroring the rest of this file's pure/mockable-only scope) —
it is exercised only by a live import, not by this suite. The ONE exception
is ``_seed_one_class``'s past-vs-future split, pinned by a dedicated
regression test below (the same instant-vs-date bug class as the reschedule
wipe/keep fix — the expander + DB writers are mocked, only the branch
decision is under test). The two pieces below that ARE otherwise pure — the
identity->expander-contract mapping and the versioned-schedule backdating
constants — get dedicated regression tests too.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import UTC, date, datetime, time, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.gym_class import RecurringUnit
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.classes.schema.classes_expander_schema import (
    ClassSlot,
    EffectiveOccurrence,
)
from src.classes.service.classes_expander import ClassesExpander
from src.presets.service.presets_service import (
    _CLASS_RECURRENCE_BACKDATE_DAYS,
    _CLASS_TIME_SLOTS,
    _MULTI_SLOT_CLASS_INDEX,
    _MULTI_SLOT_DAY,
    _PAST_HISTORY_DAYS,
    _SCHEDULE_EFFECTIVE_FROM_BACKDATE_DAYS,
    _WEEKDAY_KEYS,
    PresetsService,
)
from src.presets.service.presets_template_service import PresetsTemplateService
from src.videos.schema.videos_big_group import EDUCATIONAL_GENRES, BigGroup


def test_class_time_slots_are_times_not_strings():
    # Regression: each synthesized class_time feeds a ClassSlot.time field
    # (a Pydantic time type) and is only turned into a "HH:MM" string at
    # JSONB-serialization time (_serialize_weekday_slots) — a bare "HH:MM"
    # string here would fail Pydantic validation on ClassSlot construction.
    assert _CLASS_TIME_SLOTS  # non-empty so the modulo cycle is well-defined
    assert all(isinstance(slot, time) for slot in _CLASS_TIME_SLOTS)


def test_schedule_effective_from_predates_earliest_seeded_attendance():
    # The single imported schedule version's effective_from must land before
    # the earliest occurrence that can get seeded attendance
    # (today - _PAST_HISTORY_DAYS), so the backdated value stays honest even
    # though the FIRST version owns occurrences back to -infinity regardless.
    assert _SCHEDULE_EFFECTIVE_FROM_BACKDATE_DAYS > _PAST_HISTORY_DAYS


def test_class_recurrence_backdate_covers_past_history_window():
    # The recurrence start_date must be backdated at least as far as the
    # seeded past-history window, or the weekly recurrence wouldn't have
    # started yet for the oldest seeded occurrences.
    assert _CLASS_RECURRENCE_BACKDATE_DAYS >= _PAST_HISTORY_DAYS


def _make_presets_service() -> PresetsService:
    return PresetsService(db_pool=MagicMock(), expander=ClassesExpander())


def test_build_weekday_slots_single_slot_mon_to_fri():
    # A non-first-class index builds one slot per weekday (Mon-Fri), all at
    # the same synthesized time, with no sat/sun keys at all.
    svc = _make_presets_service()
    instructor_id = str(uuid4())

    slots = svc._build_weekday_slots(index=2, instructor_id=instructor_id)

    primary_time = _CLASS_TIME_SLOTS[2 % len(_CLASS_TIME_SLOTS)]
    for day in _WEEKDAY_KEYS:
        assert slots[day] == [
            ClassSlot(time=primary_time, instructor_id=UUID(instructor_id))
        ]
    assert "sat" not in slots
    assert "sun" not in slots


def test_build_weekday_slots_first_class_gets_genuine_multi_slot_day():
    # Regression: the FIRST imported class of every import must carry a real
    # multi-time day (two distinct times on the same weekday) so demo data
    # actually exercises the multi-time-per-day feature.
    svc = _make_presets_service()
    instructor_id = str(uuid4())

    slots = svc._build_weekday_slots(
        index=_MULTI_SLOT_CLASS_INDEX, instructor_id=instructor_id
    )

    multi_day_slots = slots[_MULTI_SLOT_DAY]
    assert len(multi_day_slots) == 2
    times = {slot.time for slot in multi_day_slots}
    assert len(times) == 2  # genuinely two distinct times, not a duplicate
    for day in _WEEKDAY_KEYS:
        if day != _MULTI_SLOT_DAY:
            assert len(slots[day]) == 1


def test_to_expander_class_is_always_weekly_with_no_end_date():
    # Preset classes are always weekly with no end date, so the expander
    # reproduces exactly the occurrences the live board would show for the
    # imported schedule. weekday_slots is passed through unchanged.
    svc = _make_presets_service()
    class_id = uuid4()
    gym_id = uuid4()
    instructor_id = str(uuid4())
    weekday_slots = svc._build_weekday_slots(index=1, instructor_id=instructor_id)

    result = svc._to_expander_class(
        class_id=class_id,
        gym_id=gym_id,
        weekday_slots=weekday_slots,
        start_date=date(2026, 1, 1),
    )

    assert result.class_id == class_id
    assert result.gym_id == gym_id
    assert result.recurring_unit == RecurringUnit.weekly
    assert result.end_date is None
    primary_time = _CLASS_TIME_SLOTS[1 % len(_CLASS_TIME_SLOTS)]
    for day in _WEEKDAY_KEYS:
        assert result.weekday_slots[day][0].time == primary_time
        assert result.weekday_slots[day][0].instructor_id == UUID(
            instructor_id
        )
    for day in ("sat", "sun"):
        assert day not in result.weekday_slots


def _seed_occurrence(*, today: date, occurred_at: datetime) -> EffectiveOccurrence:
    """A minimal occurrence landing on ``today`` (never rescheduled), whose
    effective start instant is the given ``occurred_at`` — lets a test place
    an occurrence's calendar date on "today" while its actual start instant
    sits on either side of "now"."""
    return EffectiveOccurrence(
        original_date=today,
        original_time=occurred_at.time(),
        effective_date=today,
        occurred_at=occurred_at,
        class_time=occurred_at.time(),
        duration_minutes=60,
        instructor_id=None,
        is_rescheduled=False,
        is_cancelled=False,
    )


async def test_seed_one_class_splits_by_instant_not_calendar_date():
    """Regression: the past-vs-future seeding split must compare the
    occurrence's EFFECTIVE START INSTANT to now, never its calendar date to
    today's date — the same instant-vs-date bug class as the reschedule
    wipe/keep fix. Two occurrences share ``effective_date == today``: one
    already started (occurred_at in the past) and must be seeded as
    attendance; the other is later today (occurred_at still ahead of now)
    and must get ONLY a sign-up — a `effective_date <= today` comparison
    would wrongly treat both as already-attended."""
    svc = _make_presets_service()
    now = datetime.now(UTC)
    today = now.date()
    gym_class = svc._to_expander_class(
        class_id=uuid4(),
        gym_id=uuid4(),
        weekday_slots=svc._build_weekday_slots(
            index=1, instructor_id=str(uuid4())
        ),
        start_date=today - timedelta(days=1),
    )
    already_started = _seed_occurrence(
        today=today, occurred_at=now - timedelta(hours=1)
    )
    later_today = _seed_occurrence(
        today=today, occurred_at=now + timedelta(hours=1)
    )
    svc._expander.expand = MagicMock(
        return_value=[already_started, later_today]
    )
    svc._seed_past_occurrence = AsyncMock()
    svc._seed_future_signups = AsyncMock()

    await svc._seed_one_class(
        session=AsyncMock(),
        gym_id_str=str(uuid4()),
        gym_class=gym_class,
        max_capacity=None,
        gym_tz="America/Chicago",
        now=now,
        window_start=today - timedelta(days=1),
        window_end=today + timedelta(days=1),
        pool=[],
        insert_attendance_sql="",
        insert_signup_sql="",
    )

    svc._seed_past_occurrence.assert_awaited_once()
    assert svc._seed_past_occurrence.await_args.kwargs["occ"] is already_started

    svc._seed_future_signups.assert_awaited_once()
    assert (
        svc._seed_future_signups.await_args.kwargs["original_date"]
        == later_today.original_date
    )


def test_split_name_two_parts():
    assert PresetsService._split_name("James Carter") == ("James", "Carter")


def test_split_name_splits_on_last_space():
    assert PresetsService._split_name("Mary Jo Smith") == ("Mary Jo", "Smith")


def test_split_name_single_word_uses_nonempty_fallback():
    first, last = PresetsService._split_name("Madonna")
    assert first == "Madonna"
    assert last  # non-empty fallback so the DB last_name CHECK passes


def test_split_name_blank_uses_nonempty_fallback():
    first, last = PresetsService._split_name("")
    assert first and last  # both non-empty


def test_split_name_none_uses_nonempty_fallback():
    first, last = PresetsService._split_name(None)
    assert first and last


# ── load_template_feed_page: paginated DB feed (mocked session) ───────

_TEMPLATE_GYM_ID = "mma-gym-slug"
_EDUCATIONAL_GENRE_VALUES = [g.value for g in EDUCATIONAL_GENRES]


def _make_template_service(
    mock_rows: list[dict],
) -> tuple[PresetsTemplateService, MagicMock]:
    """Build a PresetsTemplateService whose DB session returns the given rows."""
    mock_result = MagicMock()
    mock_result.mappings.return_value.all.return_value = mock_rows

    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(return_value=mock_result)

    @asynccontextmanager
    async def _session_ctx():
        yield mock_session

    mock_db = MagicMock()
    mock_db.session = _session_ctx

    svc = PresetsTemplateService(db_pool=mock_db)
    return svc, mock_session


def _template_video_row(**overrides: object) -> dict:
    """A minimal valid pool-video row with a ``total`` column."""
    base = {
        "video_id": "vid1",
        "url": "https://www.youtube.com/watch?v=vid1",
        "title": "Test Template Video",
        "description": None,
        "thumbnail_url": "https://img.youtube.com/vi/vid1/hqdefault.jpg",
        "channel_name": "Template Channel",
        "channel_url": "https://www.youtube.com/channel/tmpl",
        "channel_avatar_url": "",
        "view_count": 500,
        "like_count": None,
        "duration_seconds": 90,
        "tag": None,
        "gym_type": None,
        "source_queries": None,
        "relevance_index": 0,
        "transcript_error": None,
        "transcript": None,
        "total": 1,
    }
    return {**base, **overrides}


async def test_load_template_feed_page_no_filter_returns_page_and_total() -> None:
    """No tag filter: video_type and filter_big_group are both None in params."""
    svc, mock_session = _make_template_service(
        [_template_video_row(total=4)]
    )

    cards, total = await svc.load_template_feed_page(
        _TEMPLATE_GYM_ID,
        rejected=False,
        video_type=None,
        big_group=None,
        limit=10,
        offset=0,
    )

    assert total == 4
    assert len(cards) == 1

    params = mock_session.execute.call_args[0][1]
    assert params["video_gym_id"] == _TEMPLATE_GYM_ID
    assert params["status"] == "good"
    assert params["video_type"] is None
    assert params["filter_big_group"] is None
    assert params["limit"] == 10
    assert params["offset"] == 0
    assert params["educational_genres"] == _EDUCATIONAL_GENRE_VALUES


async def test_load_template_feed_page_video_type_filter() -> None:
    """video_type passes its string value as :video_type param."""
    svc, mock_session = _make_template_service(
        [_template_video_row(tag="analysis", total=2)]
    )

    cards, total = await svc.load_template_feed_page(
        _TEMPLATE_GYM_ID,
        video_type=VideoGenre.analysis,
        limit=20,
        offset=0,
    )

    assert total == 2
    params = mock_session.execute.call_args[0][1]
    assert params["video_type"] == VideoGenre.analysis.value
    assert params["filter_big_group"] is None


async def test_load_template_feed_page_big_group_educational() -> None:
    """big_group=EDUCATIONAL passes filter_big_group='educational' to SQL."""
    svc, mock_session = _make_template_service(
        [_template_video_row(tag="educational", total=3)]
    )

    cards, total = await svc.load_template_feed_page(
        _TEMPLATE_GYM_ID,
        big_group=BigGroup.EDUCATIONAL,
        limit=20,
        offset=0,
    )

    assert total == 3
    params = mock_session.execute.call_args[0][1]
    assert params["video_type"] is None
    assert params["filter_big_group"] == BigGroup.EDUCATIONAL.value


async def test_load_template_feed_page_big_group_entertainment() -> None:
    """big_group=ENTERTAINMENT passes filter_big_group='entertainment' to SQL."""
    svc, mock_session = _make_template_service(
        [_template_video_row(tag="memes", total=6)]
    )

    cards, total = await svc.load_template_feed_page(
        _TEMPLATE_GYM_ID,
        big_group=BigGroup.ENTERTAINMENT,
        limit=5,
        offset=5,
    )

    assert total == 6
    params = mock_session.execute.call_args[0][1]
    assert params["filter_big_group"] == BigGroup.ENTERTAINMENT.value
    assert params["limit"] == 5
    assert params["offset"] == 5


async def test_load_template_feed_page_rejected_status() -> None:
    """rejected=True passes status='rejected' to SQL."""
    svc, mock_session = _make_template_service([_template_video_row(total=1)])

    await svc.load_template_feed_page(
        _TEMPLATE_GYM_ID,
        rejected=True,
        limit=10,
        offset=0,
    )

    params = mock_session.execute.call_args[0][1]
    assert params["status"] == "rejected"


async def test_load_template_feed_page_empty_result_returns_zero_total() -> None:
    """When DB returns no rows (no matches), return ([], 0)."""
    svc, _ = _make_template_service([])

    cards, total = await svc.load_template_feed_page(
        _TEMPLATE_GYM_ID,
        limit=10,
        offset=0,
    )

    assert cards == []
    assert total == 0


# ── list_template_cards: bad discipline guard ──────────────────────────


def _catalog_row(**overrides: object) -> dict:
    """A minimal catalog row as returned by presets_list_template_cards.sql."""
    base = {
        "gym_id": "mma-gym",
        "gym_type": '["mma"]',  # JSON-encoded array (raw string from driver)
        "theme": "classic-dark",
        "video_count": 10,
        "has_classes": False,
        "has_rewards": False,
    }
    return {**base, **overrides}


def _make_catalog_service(mock_rows: list[dict]) -> PresetsTemplateService:
    """Build a PresetsTemplateService whose DB session returns the given rows."""
    mock_result = MagicMock()
    mock_result.mappings.return_value.all.return_value = mock_rows

    mock_session = AsyncMock()
    mock_session.execute = AsyncMock(return_value=mock_result)

    from contextlib import asynccontextmanager

    @asynccontextmanager
    async def _session_ctx():
        yield mock_session

    mock_db = MagicMock()
    mock_db.session = _session_ctx
    return PresetsTemplateService(db_pool=mock_db)


async def test_list_template_cards_bad_discipline_skipped() -> None:
    """A row whose first discipline is not a valid GymType is skipped, not a 500."""
    good_row = _catalog_row(gym_id="boxing-gym", gym_type='["boxing"]')
    bad_row = _catalog_row(gym_id="bad-gym", gym_type='["definitely_not_a_discipline"]')

    svc = _make_catalog_service([good_row, bad_row])
    page = await svc.list_template_cards(limit=10, offset=0)

    # The bad row is skipped; the good row is included.
    assert page.total == 2  # total is pre-guard (all items count)
    assert len(page.gyms) == 1
    assert page.gyms[0].video_gym_id == "boxing-gym"


async def test_list_template_cards_empty_discipline_skipped() -> None:
    """A row with an empty gym_type list is skipped (IndexError guard)."""
    good_row = _catalog_row(gym_id="mma-gym", gym_type='["mma"]')
    empty_disc_row = _catalog_row(gym_id="empty-gym", gym_type="[]")

    svc = _make_catalog_service([good_row, empty_disc_row])
    page = await svc.list_template_cards(limit=10, offset=0)

    assert len(page.gyms) == 1
    assert page.gyms[0].video_gym_id == "mma-gym"


# ── the no-show top-up guarantee ─────────────────────────────────────────


async def test_ensure_no_shows_gives_every_pool_member_at_least_one() -> None:
    """EVERY pool member ends the import with >=1 no-show: members the
    organic draw left at zero get topped up on past occurrences they
    neither attended nor signed up for; members who already no-showed are
    left alone (no extra inserts for them)."""
    from src.presets.service.presets_service import _PastSeed

    svc = _make_presets_service()
    svc._insert_signups = AsyncMock()

    covered = uuid4()  # already no-showed organically
    uncovered_a = uuid4()  # attended one, no-showed nowhere
    uncovered_b = uuid4()  # untouched entirely
    pool = [(m, uuid4(), uuid4()) for m in (covered, uncovered_a, uncovered_b)]

    seeds = [
        _PastSeed(
            class_id=uuid4(),
            original_date=date(2026, 6, 22),
            original_time=time(6, 0),
            attended={uncovered_a},
            signed={covered},
            no_shows={covered},
            max_capacity=None,
        ),
        _PastSeed(
            class_id=uuid4(),
            original_date=date(2026, 6, 24),
            original_time=time(18, 30),
            attended=set(),
            signed=set(),
            no_shows=set(),
            max_capacity=None,
        ),
    ]

    await svc._ensure_no_shows(
        session=MagicMock(), gym_id_str=str(uuid4()), pool=pool,
        past_seeds=seeds, insert_signup_sql="",
    )

    no_show_members = {m for s in seeds for m in s.no_shows}
    assert {covered, uncovered_a, uncovered_b} <= no_show_members
    # The topped-up members' rows were actually written, one member per call.
    written = {
        member_id
        for call in svc._insert_signups.await_args_list
        for member_id in call.args[5]
    }
    assert {uncovered_a, uncovered_b} <= written
    assert covered not in written  # already covered — no extra insert
    # A top-up never lands where the member attended or already signed up.
    for seed in seeds:
        assert seed.no_shows.isdisjoint(seed.attended)
