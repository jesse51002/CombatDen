"""Service-level edge cases for RanksService.

Covers the non-trivial product rules:
- Backfill triggers (create / from-preset / set-enabled).
- Delete-and-downgrade (lower / higher / NULL).
- Update validations.

We mock the DB-pool session so the SQL strings flow through but no
real database is touched. Each test asserts which SQL files were
executed (via the loaded SQL content) and what params were passed.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    FromPresetRequest,
    RankCreateRequest,
    RankEnabledRequest,
    RankUpdateData,
)
from src.ranks.service.ranks_service import RanksService


def _load(name: str) -> str:
    return (SQL_DIR / name).read_text()


def _make_session_mock(execute_side_effect: list[MagicMock]) -> MagicMock:
    """Build a session double that returns the given results in order."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(side_effect=execute_side_effect)
    session.commit = AsyncMock()
    return session


def _make_pool_mock(session: MagicMock) -> MagicMock:
    pool = MagicMock()
    pool.session.return_value = session
    pool.execute_with_retry = AsyncMock()
    return pool


def _executed_sql_strings(session: MagicMock) -> list[str]:
    """Return the .text attribute of each SQL textclause executed."""
    return [c.args[0].text for c in session.execute.await_args_list]


# ---------- create_rank backfill rules ----------


@pytest.mark.asyncio
async def test_create_rank_runs_backfill_when_enabled():
    """create_rank executes backfill SQL when gym is enabled."""
    gym_id = uuid4()
    rank_id = uuid4()

    insert_result = MagicMock()
    insert_result.mappings.return_value.fetchone.return_value = {
        "rank_id": rank_id,
        "gym_id": gym_id,
        "main_rank_num_order": 0,
        "sub_rank_num_order": 0,
        "main_name": "White",
        "sub_name": "0 stripes",
        "classes_till_rankup": 15,
        "image_url": None,
        "color": "#FFFFFF",
        "created_at": "2026-01-01T00:00:00Z",
    }
    enabled_result = MagicMock()
    enabled_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": True,
    }
    backfill_result = MagicMock()

    session = _make_session_mock([insert_result, enabled_result, backfill_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    request = RankCreateRequest(
        gym_id=gym_id,
        main_rank_num_order=0,
        sub_rank_num_order=0,
        main_name="White",
        sub_name="0 stripes",
        classes_till_rankup=15,
    )
    await service.create_rank(request)

    sqls = _executed_sql_strings(session)
    assert _load("insert_rank.sql") in sqls
    assert _load("backfill_lowest_rank.sql") in sqls
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_create_rank_skips_backfill_when_disabled():
    """create_rank does NOT run backfill SQL when gym is disabled."""
    gym_id = uuid4()
    rank_id = uuid4()

    insert_result = MagicMock()
    insert_result.mappings.return_value.fetchone.return_value = {
        "rank_id": rank_id,
        "gym_id": gym_id,
        "main_rank_num_order": 0,
        "sub_rank_num_order": 0,
        "main_name": "White",
        "sub_name": "0 stripes",
        "classes_till_rankup": 15,
        "image_url": None,
        "color": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    enabled_result = MagicMock()
    enabled_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": False,
    }

    session = _make_session_mock([insert_result, enabled_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    request = RankCreateRequest(
        gym_id=gym_id,
        main_rank_num_order=0,
        sub_rank_num_order=0,
        main_name="White",
        sub_name="0 stripes",
        classes_till_rankup=15,
    )
    await service.create_rank(request)

    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls


# ---------- from_preset ----------


@pytest.mark.asyncio
async def test_from_preset_runs_backfill_when_enabled():
    gym_id = uuid4()

    insert_result = MagicMock()
    enabled_result = MagicMock()
    enabled_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": True,
    }
    backfill_result = MagicMock()
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = []

    session = _make_session_mock(
        [insert_result, enabled_result, backfill_result, list_result],
    )
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    from schema.gym_rank import GymType  # noqa: PLC0415

    await service.from_preset(
        FromPresetRequest(gym_id=gym_id, gym_type=GymType.bjj),
    )

    sqls = _executed_sql_strings(session)
    assert _load("insert_ranks_from_preset.sql") in sqls
    assert _load("backfill_lowest_rank.sql") in sqls
    assert _load("list_ranks.sql") in sqls


@pytest.mark.asyncio
async def test_from_preset_skips_backfill_when_disabled():
    gym_id = uuid4()
    insert_result = MagicMock()
    enabled_result = MagicMock()
    enabled_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": False,
    }
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = []

    session = _make_session_mock([insert_result, enabled_result, list_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    from schema.gym_rank import GymType  # noqa: PLC0415

    await service.from_preset(
        FromPresetRequest(gym_id=gym_id, gym_type=GymType.mma),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls


# ---------- set_rank_enabled transitions ----------


@pytest.mark.asyncio
async def test_set_rank_enabled_false_to_true_runs_backfill():
    gym_id = uuid4()
    current_result = MagicMock()
    current_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": False,
    }
    update_result = MagicMock()
    update_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": True,
    }
    backfill_result = MagicMock()

    session = _make_session_mock([current_result, update_result, backfill_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    await service.set_rank_enabled(
        RankEnabledRequest(gym_id=gym_id, is_rank_enabled=True),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") in sqls


@pytest.mark.asyncio
async def test_set_rank_enabled_true_to_false_skips_backfill():
    gym_id = uuid4()
    current_result = MagicMock()
    current_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": True,
    }
    update_result = MagicMock()
    update_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": False,
    }

    session = _make_session_mock([current_result, update_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    await service.set_rank_enabled(
        RankEnabledRequest(gym_id=gym_id, is_rank_enabled=False),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls


@pytest.mark.asyncio
async def test_set_rank_enabled_true_to_true_skips_backfill():
    """No-op transition (already enabled) does NOT re-run backfill."""
    gym_id = uuid4()
    current_result = MagicMock()
    current_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": True,
    }
    update_result = MagicMock()
    update_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "is_rank_enabled": True,
    }
    session = _make_session_mock([current_result, update_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    await service.set_rank_enabled(
        RankEnabledRequest(gym_id=gym_id, is_rank_enabled=True),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls


@pytest.mark.asyncio
async def test_set_rank_enabled_404_when_gym_missing():
    gym_id = uuid4()
    current_result = MagicMock()
    current_result.mappings.return_value.fetchone.return_value = None
    session = _make_session_mock([current_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    with pytest.raises(ValueError, match="Gym not found"):
        await service.set_rank_enabled(
            RankEnabledRequest(gym_id=gym_id, is_rank_enabled=True),
        )


# ---------- delete_rank downgrade strategies ----------


@pytest.mark.asyncio
async def test_delete_rank_uses_lower_neighbor_when_present():
    """Deleting a mid-ladder rank reassigns members to the next-lower
    rank, then DELETEs the row."""
    rank_id = uuid4()
    gym_id = uuid4()
    lower_id = uuid4()
    higher_id = uuid4()

    neighbor_result = MagicMock()
    neighbor_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "lower_rank_id": lower_id,
        "higher_rank_id": higher_id,
    }
    reassign_result = MagicMock()
    delete_result = MagicMock()

    session = _make_session_mock(
        [neighbor_result, reassign_result, delete_result],
    )
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    await service.delete_rank(rank_id)

    reassign_call = session.execute.await_args_list[1]
    params = reassign_call.args[1]
    assert params["new_rank_id"] == str(lower_id)
    assert params["old_rank_id"] == str(rank_id)
    assert params["gym_id"] == str(gym_id)

    sqls = _executed_sql_strings(session)
    assert _load("reassign_members_rank.sql") in sqls
    assert _load("delete_rank.sql") in sqls
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_delete_rank_falls_back_to_higher_when_no_lower():
    """Deleting the lowest rank (no lower) falls back to next-higher."""
    rank_id = uuid4()
    gym_id = uuid4()
    higher_id = uuid4()

    neighbor_result = MagicMock()
    neighbor_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "lower_rank_id": None,
        "higher_rank_id": higher_id,
    }
    reassign_result = MagicMock()
    delete_result = MagicMock()
    session = _make_session_mock(
        [neighbor_result, reassign_result, delete_result],
    )
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    await service.delete_rank(rank_id)

    params = session.execute.await_args_list[1].args[1]
    assert params["new_rank_id"] == str(higher_id)


@pytest.mark.asyncio
async def test_delete_rank_sets_null_when_only_rank():
    """Deleting the only rank sets affected members' rank to NULL."""
    rank_id = uuid4()
    gym_id = uuid4()

    neighbor_result = MagicMock()
    neighbor_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "lower_rank_id": None,
        "higher_rank_id": None,
    }
    reassign_result = MagicMock()
    delete_result = MagicMock()
    session = _make_session_mock(
        [neighbor_result, reassign_result, delete_result],
    )
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    await service.delete_rank(rank_id)

    params = session.execute.await_args_list[1].args[1]
    assert params["new_rank_id"] is None


@pytest.mark.asyncio
async def test_delete_rank_404_when_missing():
    """Delete of a non-existent rank surfaces a ValueError."""
    rank_id = uuid4()
    neighbor_result = MagicMock()
    neighbor_result.mappings.return_value.fetchone.return_value = None
    session = _make_session_mock([neighbor_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    with pytest.raises(ValueError, match="Rank not found"):
        await service.delete_rank(rank_id)


@pytest.mark.asyncio
async def test_delete_rank_runs_reassign_and_delete_in_same_session():
    """Reassign and DELETE share one session — a real DB rollback
    would undo both atomically. We assert both calls hit the same
    session object before commit."""
    rank_id = uuid4()
    gym_id = uuid4()

    neighbor_result = MagicMock()
    neighbor_result.mappings.return_value.fetchone.return_value = {
        "gym_id": gym_id,
        "lower_rank_id": None,
        "higher_rank_id": None,
    }
    reassign_result = MagicMock()
    delete_result = MagicMock()
    session = _make_session_mock(
        [neighbor_result, reassign_result, delete_result],
    )
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    await service.delete_rank(rank_id)

    # Reassign was executed before delete on the same session.
    sqls = _executed_sql_strings(session)
    assert sqls.index(_load("reassign_members_rank.sql")) < sqls.index(
        _load("delete_rank.sql"),
    )


# ---------- update_rank rules ----------


def test_immutable_columns_guard_fires_on_rank_id_or_gym_id():
    """The frozenset that update_rank validates against contains
    rank_id, gym_id, and created_at — so any future caller
    constructing the update dict by hand still fails closed."""
    from schema.immutable_columns import GYM_RANKS  # noqa: PLC0415

    from src.shared.column_guard import validate_mutable_columns  # noqa: PLC0415

    for col in ("rank_id", "gym_id", "created_at"):
        with pytest.raises(ValueError, match="immutable"):
            validate_mutable_columns(GYM_RANKS, {col, "main_name"})


@pytest.mark.asyncio
async def test_update_rank_400_when_no_fields():
    """Empty update data raises a clear 'no fields' error."""
    pool = _make_pool_mock(_make_session_mock([]))
    service = RanksService(pool)
    with pytest.raises(ValueError, match="No fields"):
        await service.update_rank(uuid4(), RankUpdateData())


@pytest.mark.asyncio
async def test_update_rank_404_when_returning_empty():
    """A successful UPDATE that matched zero rows raises Rank not found."""
    pool = _make_pool_mock(_make_session_mock([]))
    pool.execute_with_retry = AsyncMock(return_value=None)
    service = RanksService(pool)
    with pytest.raises(ValueError, match="Rank not found"):
        await service.update_rank(uuid4(), RankUpdateData(main_name="X"))


# ---------- get_all_presets_grouped grouping logic ----------


@pytest.mark.asyncio
async def test_get_all_presets_grouped_handles_boundaries():
    """Single-pass grouper opens a new MainRankPresetGroup whenever
    (gym_type, main_rank_num_order) changes."""
    rows = [
        {
            "preset_id": uuid4(),
            "gym_type": "bjj",
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "White",
            "sub_name": "0 stripes",
            "classes_till_rankup": 15,
            "image_url": None,
            "color": "#FFFFFF",
        },
        {
            "preset_id": uuid4(),
            "gym_type": "bjj",
            "main_rank_num_order": 0,
            "sub_rank_num_order": 1,
            "main_name": "White",
            "sub_name": "1 stripe",
            "classes_till_rankup": 15,
            "image_url": None,
            "color": "#FFFFFF",
        },
        {
            "preset_id": uuid4(),
            "gym_type": "bjj",
            "main_rank_num_order": 1,
            "sub_rank_num_order": 0,
            "main_name": "Blue",
            "sub_name": "0 stripes",
            "classes_till_rankup": 20,
            "image_url": None,
            "color": "#1F6FEB",
        },
        {
            "preset_id": uuid4(),
            "gym_type": "mma",
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "Beginner",
            "sub_name": "",
            "classes_till_rankup": 20,
            "image_url": None,
            "color": "#9CA3AF",
        },
    ]
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = rows
    session = _make_session_mock([list_result])
    pool = _make_pool_mock(session)
    service = RanksService(pool)

    response = await service.get_all_presets_grouped()

    from schema.gym_rank import GymType  # noqa: PLC0415

    assert set(response.presets.keys()) == {GymType.bjj, GymType.mma}
    bjj = response.presets[GymType.bjj]
    assert len(bjj) == 2
    assert bjj[0].main_name == "White"
    assert len(bjj[0].sub_ranks) == 2
    assert bjj[1].main_name == "Blue"
    assert len(bjj[1].sub_ranks) == 1
    mma = response.presets[GymType.mma]
    assert len(mma) == 1
    assert mma[0].main_name == "Beginner"
