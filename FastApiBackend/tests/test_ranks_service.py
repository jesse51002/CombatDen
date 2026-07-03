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
    RankPromoteMemberRequest,
    RankRenameGroupRequest,
    RankReorderItem,
    RankReorderRequest,
    RankSetMemberRequest,
    RankUpdateData,
)
from src.ranks.service.ranks_service import RanksService
from tests.conftest import make_rank_row


def _load(name: str) -> str:
    return (SQL_DIR / name).read_text()


def _result(value: object, *, many: bool = False) -> MagicMock:
    """A session.execute() result whose mappings() yields `value`."""
    result = MagicMock()
    if many:
        result.mappings.return_value.all.return_value = value
    else:
        result.mappings.return_value.fetchone.return_value = value
    return result


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


# ---------- promote_member ----------


def _two_rank_ladder(gym_id) -> tuple[str, str, list[dict]]:
    """A two-rung ladder (lowest, highest) and its rank ids."""
    low_id = str(uuid4())
    high_id = str(uuid4())
    ladder = [
        make_rank_row(rank_id=low_id, gym_id=str(gym_id), main_name="White"),
        make_rank_row(
            rank_id=high_id,
            gym_id=str(gym_id),
            main_rank_num_order=1,
            main_name="Blue",
        ),
    ]
    return low_id, high_id, ladder


@pytest.mark.asyncio
async def test_promote_member_null_rank_assigns_lowest():
    """A rank-less member is promoted to the lowest rank."""
    gym_id = uuid4()
    member_id = uuid4()
    low_id, _high_id, ladder = _two_rank_ladder(gym_id)

    session = _make_session_mock(
        [
            _result({"current_rank_id": None, "gym_id": gym_id}),
            _result(ladder, many=True),
            _result({"member_id": member_id, "current_rank_id": low_id}),
            _result(None),  # insert_rank_activity
        ],
    )
    service = RanksService(_make_pool_mock(session))

    response = await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    assert str(response.new_rank.rank_id) == low_id
    set_params = session.execute.await_args_list[2].args[1]
    assert set_params["new_rank_id"] == low_id


@pytest.mark.asyncio
async def test_promote_member_advances_one_step():
    """A member on the lowest rank advances to the next rank up."""
    gym_id = uuid4()
    member_id = uuid4()
    low_id, high_id, ladder = _two_rank_ladder(gym_id)

    session = _make_session_mock(
        [
            _result({"current_rank_id": low_id, "gym_id": gym_id}),
            _result(ladder, many=True),
            _result({"member_id": member_id, "current_rank_id": high_id}),
            _result(None),
        ],
    )
    service = RanksService(_make_pool_mock(session))

    response = await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    assert str(response.new_rank.rank_id) == high_id


@pytest.mark.asyncio
async def test_promote_member_raises_at_top_rank():
    """Promoting a member already at the highest rank raises (→409)."""
    gym_id = uuid4()
    member_id = uuid4()
    _low_id, high_id, ladder = _two_rank_ladder(gym_id)

    session = _make_session_mock(
        [
            _result({"current_rank_id": high_id, "gym_id": gym_id}),
            _result(ladder, many=True),
        ],
    )
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="highest rank"):
        await service.promote_member(
            RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
        )


@pytest.mark.asyncio
async def test_promote_member_404_when_member_missing():
    """No member row → ValueError (router maps to 404)."""
    gym_id = uuid4()
    member_id = uuid4()
    session = _make_session_mock([_result(None)])
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="Member not found"):
        await service.promote_member(
            RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
        )


@pytest.mark.asyncio
async def test_promote_member_404_when_wrong_gym():
    """A member belonging to another gym is not found here."""
    gym_id = uuid4()
    other_gym = uuid4()
    member_id = uuid4()
    session = _make_session_mock(
        [_result({"current_rank_id": None, "gym_id": other_gym})],
    )
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="not found"):
        await service.promote_member(
            RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
        )


@pytest.mark.asyncio
async def test_promote_member_logs_activity_in_same_session():
    """The rank UPDATE and the audit activity share one committed
    session — both run before commit, update before activity."""
    gym_id = uuid4()
    member_id = uuid4()
    low_id, high_id, ladder = _two_rank_ladder(gym_id)

    session = _make_session_mock(
        [
            _result({"current_rank_id": low_id, "gym_id": gym_id}),
            _result(ladder, many=True),
            _result({"member_id": member_id, "current_rank_id": high_id}),
            _result(None),
        ],
    )
    service = RanksService(_make_pool_mock(session))

    await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    sqls = _executed_sql_strings(session)
    assert sqls.index(_load("set_member_rank.sql")) < sqls.index(
        _load("insert_rank_activity.sql"),
    )
    session.commit.assert_awaited_once()


# ---------- set_member_rank ----------


@pytest.mark.asyncio
async def test_set_member_rank_to_explicit_rank_logs_change():
    """Setting an explicit rank validates the target and logs it."""
    gym_id = uuid4()
    member_id = uuid4()
    old_id = str(uuid4())
    target_id = str(uuid4())
    target_row = make_rank_row(rank_id=target_id, gym_id=str(gym_id))

    session = _make_session_mock(
        [
            _result({"current_rank_id": old_id, "gym_id": gym_id}),
            _result(target_row),  # _read_rank_in_gym (get_rank.sql)
            _result({"member_id": member_id, "current_rank_id": target_id}),
            _result(None),  # insert_rank_activity
        ],
    )
    service = RanksService(_make_pool_mock(session))

    response = await service.set_member_rank(
        RankSetMemberRequest(
            gym_id=gym_id,
            member_id=member_id,
            rank_id=target_id,
        ),
    )

    assert str(response.new_rank.rank_id) == target_id
    sqls = _executed_sql_strings(session)
    assert _load("insert_rank_activity.sql") in sqls


@pytest.mark.asyncio
async def test_set_member_rank_unassign_writes_null_and_no_target_read():
    """Unassigning (rank_id=None) skips the target read and writes NULL."""
    gym_id = uuid4()
    member_id = uuid4()
    old_id = str(uuid4())

    session = _make_session_mock(
        [
            _result({"current_rank_id": old_id, "gym_id": gym_id}),
            _result({"member_id": member_id, "current_rank_id": None}),
            _result(None),  # insert_rank_activity (rank changed → logged)
        ],
    )
    service = RanksService(_make_pool_mock(session))

    response = await service.set_member_rank(
        RankSetMemberRequest(gym_id=gym_id, member_id=member_id, rank_id=None),
    )

    assert response.new_rank is None
    sqls = _executed_sql_strings(session)
    assert _load("get_rank.sql") not in sqls  # no target lookup
    set_params = session.execute.await_args_list[1].args[1]
    assert set_params["new_rank_id"] is None


@pytest.mark.asyncio
async def test_set_member_rank_404_when_target_in_other_gym():
    """A target rank in another gym is rejected as not found."""
    gym_id = uuid4()
    member_id = uuid4()
    target_id = str(uuid4())
    target_row = make_rank_row(rank_id=target_id, gym_id=str(uuid4()))

    session = _make_session_mock(
        [
            _result({"current_rank_id": None, "gym_id": gym_id}),
            _result(target_row),
        ],
    )
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="Rank not found"):
        await service.set_member_rank(
            RankSetMemberRequest(
                gym_id=gym_id,
                member_id=member_id,
                rank_id=target_id,
            ),
        )


# ---------- reorder_ranks ----------


def _ladder_rows(gym_id, *rank_ids) -> list[dict]:
    """A gym ladder with one main-rank row per given id, in order."""
    return [
        make_rank_row(
            rank_id=str(rid),
            gym_id=str(gym_id),
            main_rank_num_order=i,
            sub_rank_num_order=0,
        )
        for i, rid in enumerate(rank_ids)
    ]


@pytest.mark.asyncio
async def test_reorder_ranks_shifts_before_finalizing():
    """Reorder validates against the ladder, shifts every row out of
    the target space, finalizes, then re-lists — one committed
    session."""
    gym_id = uuid4()
    rank_a = uuid4()
    rank_b = uuid4()

    session = _make_session_mock(
        [
            _result(_ladder_rows(gym_id, rank_a, rank_b), many=True),
            _result(None),  # shift
            _result(None),  # finalize
            _result([], many=True),  # final list
        ],
    )
    service = RanksService(_make_pool_mock(session))

    await service.reorder_ranks(
        RankReorderRequest(
            gym_id=gym_id,
            ranks=[
                RankReorderItem(
                    rank_id=rank_a,
                    main_rank_num_order=1,
                    sub_rank_num_order=0,
                ),
                RankReorderItem(
                    rank_id=rank_b,
                    main_rank_num_order=0,
                    sub_rank_num_order=0,
                ),
            ],
        ),
    )

    sqls = _executed_sql_strings(session)
    last_list_index = len(sqls) - 1 - sqls[::-1].index(_load("list_ranks.sql"))
    assert (
        sqls.index(_load("list_ranks.sql"))  # validation pre-read
        < sqls.index(_load("reorder_ranks_shift.sql"))
        < sqls.index(_load("reorder_ranks_finalize.sql"))
        < last_list_index
    )
    session.commit.assert_awaited_once()


def _reorder_request(gym_id, *items) -> RankReorderRequest:
    return RankReorderRequest(
        gym_id=gym_id,
        ranks=[
            RankReorderItem(
                rank_id=rid,
                main_rank_num_order=main,
                sub_rank_num_order=sub,
            )
            for rid, main, sub in items
        ],
    )


@pytest.mark.asyncio
async def test_reorder_ranks_rejects_unknown_rank():
    """A payload rank_id outside the gym's ladder is a ValueError —
    never a silent no-op."""
    gym_id = uuid4()
    known = uuid4()

    session = _make_session_mock(
        [_result(_ladder_rows(gym_id, known), many=True)],
    )
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="not in this gym's ladder"):
        await service.reorder_ranks(
            _reorder_request(gym_id, (known, 0, 0), (uuid4(), 1, 0)),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_reorder_ranks_rejects_partial_payload():
    """A payload that misses part of the ladder is a ValueError —
    a partial apply could collide with unlisted rows."""
    gym_id = uuid4()
    rank_a = uuid4()
    rank_b = uuid4()

    session = _make_session_mock(
        [_result(_ladder_rows(gym_id, rank_a, rank_b), many=True)],
    )
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="entire ladder"):
        await service.reorder_ranks(
            _reorder_request(gym_id, (rank_a, 0, 0)),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_reorder_ranks_rejects_duplicate_position():
    """Two ranks aimed at the same (main, sub) target is a ValueError
    — the unique-order constraint would 500 at finalize otherwise."""
    gym_id = uuid4()
    rank_a = uuid4()
    rank_b = uuid4()

    session = _make_session_mock(
        [_result(_ladder_rows(gym_id, rank_a, rank_b), many=True)],
    )
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="Duplicate target position"):
        await service.reorder_ranks(
            _reorder_request(gym_id, (rank_a, 0, 0), (rank_b, 0, 0)),
        )
    session.commit.assert_not_awaited()


# ---------- whole-group operations ----------


@pytest.mark.asyncio
async def test_rename_group_updates_rows_and_returns_ladder():
    """rename_group runs the atomic group UPDATE, then re-lists."""
    gym_id = uuid4()

    session = _make_session_mock(
        [
            _result([{"rank_id": str(uuid4())}], many=True),  # rename
            _result([], many=True),  # list
        ],
    )
    service = RanksService(_make_pool_mock(session))

    await service.rename_group(
        RankRenameGroupRequest(
            gym_id=gym_id,
            main_rank_num_order=1,
            new_main_name="Blue",
        ),
    )

    sqls = _executed_sql_strings(session)
    assert sqls.index(_load("rename_rank_group.sql")) < sqls.index(
        _load("list_ranks.sql"),
    )
    rename_params = session.execute.await_args_list[0].args[1]
    assert rename_params["new_main_name"] == "Blue"
    assert rename_params["main_rank_num_order"] == 1
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_rename_group_raises_when_group_missing():
    """No rows renamed → the group doesn't exist → ValueError."""
    session = _make_session_mock([_result([], many=True)])
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="not found"):
        await service.rename_group(
            RankRenameGroupRequest(
                gym_id=uuid4(),
                main_rank_num_order=9,
                new_main_name="Blue",
            ),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_delete_group_reassigns_members_before_deleting():
    """delete_group resolves the neighbour, moves members off ALL of
    the group's sub-ranks, then deletes the rows — one session."""
    gym_id = uuid4()
    lower = uuid4()

    session = _make_session_mock(
        [
            _result(
                {
                    "gym_id": str(gym_id),
                    "lower_rank_id": str(lower),
                    "higher_rank_id": None,
                },
            ),
            _result(None),  # reassign
            _result(None),  # delete
        ],
    )
    service = RanksService(_make_pool_mock(session))

    await service.delete_group(gym_id, 2)

    sqls = _executed_sql_strings(session)
    assert (
        sqls.index(_load("get_group_neighbor_ranks.sql"))
        < sqls.index(_load("reassign_members_group.sql"))
        < sqls.index(_load("delete_rank_group.sql"))
    )
    reassign_params = session.execute.await_args_list[1].args[1]
    assert reassign_params["new_rank_id"] == str(lower)
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_delete_group_raises_when_group_missing():
    """A neighbour read with NULL gym_id means no such group."""
    session = _make_session_mock(
        [
            _result(
                {"gym_id": None, "lower_rank_id": None, "higher_rank_id": None},
            ),
        ],
    )
    service = RanksService(_make_pool_mock(session))

    with pytest.raises(ValueError, match="not found"):
        await service.delete_group(uuid4(), 3)
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_delete_group_nulls_rank_when_group_is_only_one():
    """No neighbour at all → members are unassigned (NULL), matching
    the single-rank delete's semantics."""
    gym_id = uuid4()

    session = _make_session_mock(
        [
            _result(
                {
                    "gym_id": str(gym_id),
                    "lower_rank_id": None,
                    "higher_rank_id": None,
                },
            ),
            _result(None),  # reassign
            _result(None),  # delete
        ],
    )
    service = RanksService(_make_pool_mock(session))

    await service.delete_group(gym_id, 0)

    reassign_params = session.execute.await_args_list[1].args[1]
    assert reassign_params["new_rank_id"] is None
    session.commit.assert_awaited_once()


# ---------- backfill audit logging ----------


@pytest.mark.asyncio
async def test_backfill_binds_rank_changed_activity_type():
    """The backfill statement is passed the rank_changed activity
    type — each backfilled member gets an audit row that anchors
    their progress at the backfill moment."""
    gym_id = uuid4()

    session = _make_session_mock(
        [
            _result(
                make_rank_row(rank_id=str(uuid4()), gym_id=str(gym_id)),
            ),  # insert
            _result({"is_rank_enabled": True}),  # enabled check
            _result(None),  # backfill
        ],
    )
    service = RanksService(_make_pool_mock(session))

    await service.create_rank(
        RankCreateRequest(
            gym_id=gym_id,
            main_rank_num_order=0,
            sub_rank_num_order=0,
            main_name="White",
            sub_name="Belt",
            classes_till_rankup=10,
        ),
    )

    sqls = _executed_sql_strings(session)
    backfill_index = sqls.index(_load("backfill_lowest_rank.sql"))
    backfill_params = session.execute.await_args_list[backfill_index].args[1]
    assert backfill_params["activity_type"] == "rank_changed"
