"""Service-level edge cases for RanksService (two-level rank model).

Covers the non-trivial product rules of the rebuilt domain:
- Backfill triggers (create / from-preset / set-enabled) + derived base-leaf name.
- Delete-and-downgrade (lower / higher / NULL).
- Update validations + the shrink-count clamp + the JSONB-override CAST/persist rule.
- Leaf-aware promote (within a main, across a main, top-of-ladder → 409).
- set-member-rank sub_index validation (count>0 in-range / out-of-range /
  missing, count==0 forced None, unassign).
- Two-phase full-ladder reorder guard.

We mock the DB-pool session so the SQL strings flow through but no real
database is touched. Each test asserts which SQL files were executed (via the
loaded SQL content) and what params were passed.
"""

import json
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.gym_rank import RankPresetKind, SubRankType
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    FromPresetRequest,
    RankCreateRequest,
    RankEnabledRequest,
    RankPromoteMemberRequest,
    RankReorderItem,
    RankReorderRequest,
    RankSetMemberRequest,
    RankUpdateData,
)
from src.ranks.service.ranks_members import RanksMembers
from src.ranks.service.ranks_presets import RanksPresets
from src.ranks.service.ranks_reads import RanksReads
from src.ranks.service.ranks_reorder import REORDER_SHIFT_OFFSET, RanksReorder
from src.ranks.service.ranks_service import RanksService
from src.shared.sql_loader import load_sql
from tests.conftest import make_rank_row


def _load(name: str) -> str:
    return (SQL_DIR / name).read_text()


def _sql_body(name: str) -> str:
    """The SQL file with its ``--`` comment lines stripped.

    Lets a contract test assert a token is absent from the executable
    STATEMENT without a mention in the header comment (which deliberately
    names the preserved / never-touched columns) tripping the check.
    """
    return "\n".join(
        line
        for line in _load(name).splitlines()
        if not line.lstrip().startswith("--")
    )


def _result(value: object, *, many: bool = False) -> MagicMock:
    """A session.execute() result whose mappings() yields `value`."""
    result = MagicMock()
    if many:
        result.mappings.return_value.all.return_value = value
    else:
        result.mappings.return_value.fetchone.return_value = value
    return result


def _sub_type_result(value: str = "stripes") -> MagicMock:
    """A get_gym_sub_rank_type.sql result → {'sub_rank_type': value}."""
    return _result({"sub_rank_type": value})


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


def _make_service(pool: MagicMock) -> RanksService:
    """The facade wired over its concern services, all sharing one pool.

    Mirrors the DI wiring in ``src/core/dependencies.py``: every concern
    reads/writes through the same ``db_pool``, so the mocked session flows
    through the delegated calls exactly as it did before the split.
    """
    members = RanksMembers(pool)
    reorder = RanksReorder(pool)
    presets = RanksPresets(pool, members)
    reads = RanksReads(pool)
    return RanksService(pool, members, reorder, presets, reads)


def _executed_sql_strings(session: MagicMock) -> list[str]:
    """Return the .text attribute of each SQL textclause executed."""
    return [c.args[0].text for c in session.execute.await_args_list]


def _params_for(session: MagicMock, filename: str) -> dict:
    """Params passed to the (first) execute of the given SQL file."""
    target = _load(filename)
    for call in session.execute.await_args_list:
        if call.args[0].text == target:
            return call.args[1]
    raise AssertionError(f"{filename} was not executed")


# ---------- create_rank backfill rules ----------


@pytest.mark.asyncio
async def test_create_rank_runs_backfill_when_enabled():
    """create_rank executes backfill SQL when the gym is enabled."""
    gym_id = uuid4()
    rank_id = uuid4()

    insert_result = _result(
        make_rank_row(rank_id=str(rank_id), gym_id=str(gym_id)),
    )
    enabled_result = _result({"gym_id": gym_id, "is_rank_enabled": True})
    # backfill: empty ladder → no sub_rank_type read, backfill SQL still runs.
    list_result = _result([], many=True)
    backfill_result = _result(None)

    session = _make_session_mock(
        [insert_result, enabled_result, list_result, backfill_result],
    )
    service = _make_service(_make_pool_mock(session))

    request = RankCreateRequest(
        gym_id=gym_id,
        main_rank_num_order=0,
        name="White",
        classes_to_next_major=15,
    )
    await service.create_rank(request)

    sqls = _executed_sql_strings(session)
    assert _load("insert_rank.sql") in sqls
    assert _load("backfill_lowest_rank.sql") in sqls
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_create_rank_skips_backfill_when_disabled():
    """create_rank does NOT run backfill SQL when the gym is disabled."""
    gym_id = uuid4()
    rank_id = uuid4()

    insert_result = _result(
        make_rank_row(rank_id=str(rank_id), gym_id=str(gym_id)),
    )
    enabled_result = _result({"gym_id": gym_id, "is_rank_enabled": False})

    session = _make_session_mock([insert_result, enabled_result])
    service = _make_service(_make_pool_mock(session))

    request = RankCreateRequest(
        gym_id=gym_id,
        main_rank_num_order=0,
        name="White",
        classes_to_next_major=15,
    )
    await service.create_rank(request)

    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls


@pytest.mark.asyncio
async def test_create_rank_binds_jsonb_overrides_via_cast():
    """The insert binds sub_rank_image_overrides as a json.dumps'd string
    (the SQL file wraps it in CAST(:col AS JSONB), never :col::jsonb)."""
    gym_id = uuid4()
    overrides = {"0": "https://cdn/white.png", "1": "https://cdn/white-1.png"}

    insert_result = _result(
        make_rank_row(rank_id=str(uuid4()), gym_id=str(gym_id)),
    )
    enabled_result = _result({"gym_id": gym_id, "is_rank_enabled": False})
    session = _make_session_mock([insert_result, enabled_result])
    service = _make_service(_make_pool_mock(session))

    await service.create_rank(
        RankCreateRequest(
            gym_id=gym_id,
            main_rank_num_order=0,
            name="White",
            classes_to_next_major=15,
            sub_rank_count=2,
            sub_rank_image_overrides=overrides,
        ),
    )

    insert_params = _params_for(session, "insert_rank.sql")
    assert insert_params["sub_rank_image_overrides"] == json.dumps(overrides)
    assert insert_params["sub_rank_count"] == 2


@pytest.mark.asyncio
async def test_create_rank_duplicate_position_raises_already_taken():
    """A duplicate (gym_id, main_rank_num_order) hits the ladder-position
    UNIQUE constraint → IntegrityError, surfaced as a clean 'already taken'
    ValueError the router maps to 409 (not a generic 500)."""
    gym_id = uuid4()
    session = _make_session_mock(
        [IntegrityError("INSERT", {}, Exception("unique violation"))],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="already taken"):
        await service.create_rank(
            RankCreateRequest(
                gym_id=gym_id,
                main_rank_num_order=0,
                name="White",
                classes_to_next_major=15,
            ),
        )


# ---------- from_preset ----------


@pytest.mark.asyncio
async def test_from_preset_runs_backfill_and_sets_type_when_enabled():
    gym_id = uuid4()

    insert_result = _result(None)
    type_result = _result(None)  # set_gym_sub_rank_type_from_preset.sql
    reconcile_type = _sub_type_result()  # get_gym_sub_rank_type (reconcile read)
    reconcile_result = _result(None)  # reconcile_member_sub_index_for_gym.sql
    enabled_result = _result({"gym_id": gym_id, "is_rank_enabled": True})
    backfill_list = _result([], many=True)  # backfill ladder read (empty)
    backfill_result = _result(None)
    response_list = _result([], many=True)  # response ladder

    session = _make_session_mock(
        [
            insert_result,
            type_result,
            reconcile_type,
            reconcile_result,
            enabled_result,
            backfill_list,
            backfill_result,
            response_list,
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.from_preset(
        FromPresetRequest(gym_id=gym_id, preset_kind=RankPresetKind.bjj_belts),
    )

    sqls = _executed_sql_strings(session)
    assert _load("insert_ranks_from_preset.sql") in sqls
    assert _load("set_gym_sub_rank_type_from_preset.sql") in sqls
    # Existing members are reconciled to the preset's implied style.
    assert _load("reconcile_member_sub_index_for_gym.sql") in sqls
    assert _load("backfill_lowest_rank.sql") in sqls
    assert _load("list_ranks.sql") in sqls
    # The upsert can SHRINK a rank's sub_rank_count, so the member reconcile
    # must run AFTER the upsert (to see the new counts) and after the type
    # set — otherwise a clamped-down member would be missed.
    assert (
        sqls.index(_load("insert_ranks_from_preset.sql"))
        < sqls.index(_load("set_gym_sub_rank_type_from_preset.sql"))
        < sqls.index(_load("reconcile_member_sub_index_for_gym.sql"))
    )


@pytest.mark.asyncio
async def test_from_preset_skips_backfill_when_disabled():
    gym_id = uuid4()

    session = _make_session_mock(
        [
            _result(None),  # insert_ranks_from_preset
            _result(None),  # set_gym_sub_rank_type_from_preset
            _sub_type_result("none"),  # get_gym_sub_rank_type (reconcile read)
            _result(None),  # reconcile_member_sub_index_for_gym
            _result({"gym_id": gym_id, "is_rank_enabled": False}),
            _result([], many=True),  # response ladder
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.from_preset(
        FromPresetRequest(gym_id=gym_id, preset_kind=RankPresetKind.flat),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls
    # Reconcile still runs even when the backfill is skipped.
    assert _load("reconcile_member_sub_index_for_gym.sql") in sqls


# ---------- from_preset upsert + clamp (SQL contract) ----------


def test_from_preset_sql_upserts_name_image_and_count():
    """from_preset's insert is an UPSERT: an existing ladder position is
    overwritten with the preset's name / image_url / sub_rank_count (via
    EXCLUDED), so re-applying a preset onto a gym that already has ranks
    RENAMES them + re-images + re-counts every position it shares — it no
    longer silently skips existing rows."""
    sql = _load("insert_ranks_from_preset.sql")
    assert "ON CONFLICT (gym_id, main_rank_num_order) DO UPDATE SET" in sql
    assert "name = EXCLUDED.name" in sql
    assert "image_url = EXCLUDED.image_url" in sql
    assert "sub_rank_count = EXCLUDED.sub_rank_count" in sql
    # The old skip-on-conflict behavior is gone.
    assert "DO NOTHING" not in sql


def test_from_preset_sql_preserves_threshold_and_overrides():
    """The upsert deliberately does NOT overwrite classes_to_next_major (the
    gym keeps its own threshold to the next major) and never touches
    sub_rank_image_overrides (persist-only — not even in the column list).
    Checked against the statement body so the header comment's mention of
    the preserved columns doesn't mask a real regression."""
    body = _sql_body("insert_ranks_from_preset.sql")
    assert "classes_to_next_major = EXCLUDED" not in body
    assert "sub_rank_image_overrides" not in body


def test_from_preset_sql_never_deletes_a_rank():
    """The seed-from-preset insert only ever inserts/updates rank rows — a
    rank the gym has beyond the preset's length is left untouched (there is
    no DELETE anywhere in the executable statement)."""
    body = _sql_body("insert_ranks_from_preset.sql")
    assert "DELETE" not in body.upper()


def test_reconcile_sql_clamps_members_to_post_upsert_count():
    """Because the upsert can SHRINK a rank's sub_rank_count, the SAME
    reconcile step (run AFTER the upsert, unconditionally) keeps every member
    at a valid leaf by reading the NEW per-rank count from gym_ranks
    (gr.sub_rank_count): a NULL sub_index (coming from 'none') fills to the
    base leaf 0, an in-range/over-range index is LEAST-clamped to count-1,
    and an effective count of 0 ('none' gym or a subless rank) becomes NULL.
    Post-condition for every member: effective count > 0 =>
    current_sub_index = LEAST(current_sub_index_or_0, count-1); effective
    count 0 => NULL."""
    sql = _load("reconcile_member_sub_index_for_gym.sql")
    # Clamp reads the POST-upsert count from gym_ranks and floors at the top leaf.
    assert "LEAST(m.current_sub_index, gr.sub_rank_count - 1)" in sql
    # NULL (coming from 'none') fills to the base leaf 0.
    assert "WHEN m.current_sub_index IS NULL THEN 0" in sql
    # Effective count 0 / 'none' gym => NULL.
    assert "= 'none' THEN NULL" in sql
    assert "WHEN gr.sub_rank_count = 0 THEN NULL" in sql


# ---------- set_rank_enabled transitions ----------


@pytest.mark.asyncio
async def test_set_rank_enabled_false_to_true_runs_backfill():
    gym_id = uuid4()
    session = _make_session_mock(
        [
            _result({"gym_id": gym_id, "is_rank_enabled": False}),  # current
            _result({"gym_id": gym_id, "is_rank_enabled": True}),  # update
            _result([], many=True),  # backfill ladder read (empty)
            _result(None),  # backfill SQL
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.set_rank_enabled(
        RankEnabledRequest(gym_id=gym_id, is_rank_enabled=True),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") in sqls


@pytest.mark.asyncio
async def test_set_rank_enabled_true_to_false_skips_backfill():
    gym_id = uuid4()
    session = _make_session_mock(
        [
            _result({"gym_id": gym_id, "is_rank_enabled": True}),
            _result({"gym_id": gym_id, "is_rank_enabled": False}),
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.set_rank_enabled(
        RankEnabledRequest(gym_id=gym_id, is_rank_enabled=False),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls


@pytest.mark.asyncio
async def test_set_rank_enabled_true_to_true_skips_backfill():
    """No-op transition (already enabled) does NOT re-run backfill."""
    gym_id = uuid4()
    session = _make_session_mock(
        [
            _result({"gym_id": gym_id, "is_rank_enabled": True}),
            _result({"gym_id": gym_id, "is_rank_enabled": True}),
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.set_rank_enabled(
        RankEnabledRequest(gym_id=gym_id, is_rank_enabled=True),
    )
    sqls = _executed_sql_strings(session)
    assert _load("backfill_lowest_rank.sql") not in sqls


@pytest.mark.asyncio
async def test_set_rank_enabled_404_when_gym_missing():
    gym_id = uuid4()
    session = _make_session_mock([_result(None)])
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="Gym not found"):
        await service.set_rank_enabled(
            RankEnabledRequest(gym_id=gym_id, is_rank_enabled=True),
        )


# ---------- backfill audit logging + derived base-leaf name ----------


@pytest.mark.asyncio
async def test_backfill_binds_rank_changed_activity_type():
    """The backfill statement is passed the rank_changed activity type —
    each backfilled member gets an audit row that anchors their progress
    at the backfill moment."""
    gym_id = uuid4()

    session = _make_session_mock(
        [
            _result(make_rank_row(rank_id=str(uuid4()), gym_id=str(gym_id))),
            _result({"gym_id": gym_id, "is_rank_enabled": True}),
            _result([], many=True),  # empty backfill ladder
            _result(None),  # backfill SQL
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.create_rank(
        RankCreateRequest(
            gym_id=gym_id,
            main_rank_num_order=0,
            name="White",
            classes_to_next_major=10,
        ),
    )

    backfill_params = _params_for(session, "backfill_lowest_rank.sql")
    assert backfill_params["activity_type"] == "rank_changed"


@pytest.mark.asyncio
async def test_backfill_binds_derived_base_leaf_name():
    """With a non-empty ladder the backfill pins the lowest rank's BASE
    leaf (sub-index 0 when it has sub-ranks) and binds the Python-derived
    display name — the gym's sub_rank_type drives the label (div base of
    'White' → 'White · Div 1')."""
    gym_id = uuid4()
    lowest = make_rank_row(
        rank_id=str(uuid4()),
        gym_id=str(gym_id),
        name="White",
        sub_rank_count=4,
    )

    session = _make_session_mock(
        [
            _result(make_rank_row(rank_id=str(uuid4()), gym_id=str(gym_id))),
            _result({"gym_id": gym_id, "is_rank_enabled": True}),
            _result([lowest], many=True),  # backfill ladder read
            _sub_type_result("div"),  # gym sub_rank_type
            _result(None),  # backfill SQL
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.create_rank(
        RankCreateRequest(
            gym_id=gym_id,
            main_rank_num_order=1,
            name="Blue",
            classes_to_next_major=10,
        ),
    )

    backfill_params = _params_for(session, "backfill_lowest_rank.sql")
    assert backfill_params["new_rank_name"] == "White · Div 1"


# ---------- delete_rank downgrade strategies ----------


@pytest.mark.asyncio
async def test_delete_rank_uses_lower_neighbor_when_present():
    """Deleting a mid-ladder rank reassigns members to the next-lower
    rank, then DELETEs the row."""
    rank_id = uuid4()
    gym_id = uuid4()
    lower_id = uuid4()
    higher_id = uuid4()

    neighbor_result = _result(
        {
            "gym_id": gym_id,
            "lower_rank_id": lower_id,
            "higher_rank_id": higher_id,
        },
    )
    session = _make_session_mock(
        [neighbor_result, _result(None), _result(None)],
    )
    service = _make_service(_make_pool_mock(session))

    await service.delete_rank(rank_id)

    params = _params_for(session, "reassign_members_rank.sql")
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

    neighbor_result = _result(
        {"gym_id": gym_id, "lower_rank_id": None, "higher_rank_id": higher_id},
    )
    session = _make_session_mock(
        [neighbor_result, _result(None), _result(None)],
    )
    service = _make_service(_make_pool_mock(session))

    await service.delete_rank(rank_id)

    assert _params_for(session, "reassign_members_rank.sql")["new_rank_id"] == str(
        higher_id
    )


@pytest.mark.asyncio
async def test_delete_rank_sets_null_when_only_rank():
    """Deleting the only rank sets affected members' rank to NULL."""
    rank_id = uuid4()
    gym_id = uuid4()

    neighbor_result = _result(
        {"gym_id": gym_id, "lower_rank_id": None, "higher_rank_id": None},
    )
    session = _make_session_mock(
        [neighbor_result, _result(None), _result(None)],
    )
    service = _make_service(_make_pool_mock(session))

    await service.delete_rank(rank_id)

    assert _params_for(session, "reassign_members_rank.sql")["new_rank_id"] is None


@pytest.mark.asyncio
async def test_delete_rank_404_when_missing():
    """Delete of a non-existent rank surfaces a ValueError."""
    rank_id = uuid4()
    session = _make_session_mock([_result(None)])
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="Rank not found"):
        await service.delete_rank(rank_id)


@pytest.mark.asyncio
async def test_delete_rank_runs_reassign_and_delete_in_same_session():
    """Reassign and DELETE share one session — a real DB rollback would
    undo both atomically. We assert reassign runs before delete."""
    rank_id = uuid4()
    gym_id = uuid4()

    neighbor_result = _result(
        {"gym_id": gym_id, "lower_rank_id": None, "higher_rank_id": None},
    )
    session = _make_session_mock(
        [neighbor_result, _result(None), _result(None)],
    )
    service = _make_service(_make_pool_mock(session))

    await service.delete_rank(rank_id)

    sqls = _executed_sql_strings(session)
    assert sqls.index(_load("reassign_members_rank.sql")) < sqls.index(
        _load("delete_rank.sql"),
    )


# ---------- update_rank rules ----------


def test_immutable_columns_guard_fires_on_rank_id_or_gym_id():
    """The frozenset that update_rank validates against contains rank_id,
    gym_id, created_at, and main_rank_num_order (order is reorder-only) —
    so any future caller constructing the update dict by hand still fails
    closed. image_url is NOT immutable (it is a user-writable field now)."""
    from schema.immutable_columns import GYM_RANKS  # noqa: PLC0415

    from src.shared.column_guard import validate_mutable_columns  # noqa: PLC0415

    for col in ("rank_id", "gym_id", "created_at", "main_rank_num_order"):
        with pytest.raises(ValueError, match="immutable"):
            validate_mutable_columns(GYM_RANKS, {col, "name"})

    # image_url + the overrides map are writable — no raise.
    validate_mutable_columns(GYM_RANKS, {"image_url", "sub_rank_image_overrides"})


@pytest.mark.asyncio
async def test_update_rank_400_when_no_fields():
    """Empty update data raises a clear 'no fields' error."""
    service = _make_service(_make_pool_mock(_make_session_mock([])))
    with pytest.raises(ValueError, match="No fields"):
        await service.update_rank(uuid4(), RankUpdateData())


@pytest.mark.asyncio
async def test_update_rank_404_when_returning_empty():
    """A successful UPDATE that matched zero rows raises Rank not found."""
    session = _make_session_mock([_result(None)])
    service = _make_service(_make_pool_mock(session))
    with pytest.raises(ValueError, match="Rank not found"):
        await service.update_rank(uuid4(), RankUpdateData(name="X"))


@pytest.mark.asyncio
async def test_update_rank_shrunk_count_reconciles_members_and_keeps_overrides():
    """When sub_rank_count is in the payload, every member of the gym is
    re-fitted in the SAME transaction via the shared reconcile (which reads
    the live per-rank counts to clamp down / fill up / NULL) — but the
    overrides map is never pruned (persist-only), so it is not part of the
    SET clause here."""
    rank_id = uuid4()
    gym_id = uuid4()
    updated_row = make_rank_row(
        rank_id=str(rank_id),
        gym_id=str(gym_id),
        sub_rank_count=2,
    )

    session = _make_session_mock(
        # update, then the gym sub_rank_type read, then the reconcile
        [_result(updated_row), _sub_type_result("stripes"), _result(None)],
    )
    service = _make_service(_make_pool_mock(session))

    await service.update_rank(rank_id, RankUpdateData(sub_rank_count=2))

    sqls = _executed_sql_strings(session)
    assert _load("reconcile_member_sub_index_for_gym.sql") in sqls

    # update_rank.sql is templated ({set_clause}), so grab the first execute
    # (the UPDATE) by position rather than by raw file content.
    update_params = session.execute.await_args_list[0].args[1]
    assert update_params["sub_rank_count"] == 2
    # Persist-only: the overrides map is NOT rewritten on a count change.
    assert "sub_rank_image_overrides" not in update_params

    reconcile_params = _params_for(
        session, "reconcile_member_sub_index_for_gym.sql"
    )
    assert reconcile_params["sub_rank_type"] == "stripes"
    assert reconcile_params["gym_id"] == str(gym_id)


@pytest.mark.asyncio
async def test_update_rank_grown_count_reconciles_members():
    """Growing sub_rank_count across the 0 boundary on a stripes gym routes
    through the shared reconcile (NOT a down-only clamp): a member stranded
    at a NULL sub_index while the effective count is now > 0 would violate
    the leaf invariant, so the reconcile must run to fill NULL→0 by reading
    the live per-rank count. Regression for the leaf-invariant GROW gap the
    deleted clamp_member_sub_index.sql left open (it only clamped DOWN and
    filtered current_sub_index IS NOT NULL)."""
    rank_id = uuid4()
    gym_id = uuid4()
    updated_row = make_rank_row(
        rank_id=str(rank_id),
        gym_id=str(gym_id),
        sub_rank_count=5,
    )

    session = _make_session_mock(
        [_result(updated_row), _sub_type_result("stripes"), _result(None)],
    )
    service = _make_service(_make_pool_mock(session))

    await service.update_rank(rank_id, RankUpdateData(sub_rank_count=5))

    sqls = _executed_sql_strings(session)
    assert _load("reconcile_member_sub_index_for_gym.sql") in sqls
    reconcile_params = _params_for(
        session, "reconcile_member_sub_index_for_gym.sql"
    )
    assert reconcile_params["sub_rank_type"] == "stripes"
    assert reconcile_params["gym_id"] == str(gym_id)


@pytest.mark.asyncio
async def test_update_rank_overrides_use_cast_and_skip_reconcile():
    """Updating only the overrides map binds it as CAST(:col AS JSONB)
    over a json.dumps'd value and runs NO reconcile (count unchanged)."""
    rank_id = uuid4()
    overrides = {"1": "https://cdn/white-1.png"}
    updated_row = make_rank_row(
        rank_id=str(rank_id),
        gym_id=str(uuid4()),
        sub_rank_image_overrides=overrides,
    )

    session = _make_session_mock([_result(updated_row)])
    service = _make_service(_make_pool_mock(session))

    await service.update_rank(
        rank_id,
        RankUpdateData(sub_rank_image_overrides=overrides),
    )

    sqls = _executed_sql_strings(session)
    assert _load("reconcile_member_sub_index_for_gym.sql") not in sqls

    update_call = session.execute.await_args_list[0]
    assert "CAST(:sub_rank_image_overrides AS JSONB)" in update_call.args[0].text
    assert ":sub_rank_image_overrides::jsonb" not in update_call.args[0].text
    assert update_call.args[1]["sub_rank_image_overrides"] == json.dumps(overrides)


def test_update_rank_sql_binds_only_real_params():
    """update_rank.sql runs through text(), which scans the WHOLE statement
    — comments included — for :name bind markers. A generic placeholder like
    :col in the header comment becomes an orphan bind param no code supplies,
    so every rank edit 500s ("A value is required for bind parameter 'col'").
    Guard: the templated statement binds ONLY the real columns + rank_id.
    (Regression: a 'col' orphan was hiding in the comment; the mocked update
    tests build text(sql) but never compile it against params, so they
    couldn't catch it.)"""
    set_clause = (
        "name = :name, classes_to_next_major = :classes_to_next_major, "
        "sub_rank_count = :sub_rank_count, image_url = :image_url, "
        "sub_rank_image_overrides = CAST(:sub_rank_image_overrides AS JSONB)"
    )
    sql = load_sql(SQL_DIR / "update_rank.sql", {"set_clause": set_clause})
    binds = set(text(sql)._bindparams.keys())
    assert binds == {
        "name",
        "classes_to_next_major",
        "sub_rank_count",
        "image_url",
        "sub_rank_image_overrides",
        "rank_id",
    }, f"unexpected bind params (comment placeholder leaked?): {binds}"


# ---------- get_all_presets_grouped grouping logic ----------


@pytest.mark.asyncio
async def test_get_all_presets_grouped_buckets_by_preset_kind():
    """The single-pass grouper opens a new list per preset_kind and keeps
    each preset kind's main rows in ladder order. implied_sub_rank_type
    surfaces on the stripes preset."""
    rows = [
        {
            "preset_id": uuid4(),
            "preset_kind": "bjj_belts",
            "main_rank_num_order": 0,
            "name": "White",
            "image_url": None,
            "classes_to_next_major": 15,
            "sub_rank_count": 0,
            "implied_sub_rank_type": None,
        },
        {
            "preset_id": uuid4(),
            "preset_kind": "bjj_belts",
            "main_rank_num_order": 1,
            "name": "Blue",
            "image_url": None,
            "classes_to_next_major": 20,
            "sub_rank_count": 0,
            "implied_sub_rank_type": None,
        },
        {
            "preset_id": uuid4(),
            "preset_kind": "bjj_belts_stripes",
            "main_rank_num_order": 0,
            "name": "White",
            "image_url": None,
            "classes_to_next_major": 15,
            "sub_rank_count": 5,
            "implied_sub_rank_type": "stripes",
        },
        {
            "preset_id": uuid4(),
            "preset_kind": "flat",
            "main_rank_num_order": 0,
            "name": "Member",
            "image_url": None,
            "classes_to_next_major": 20,
            "sub_rank_count": 0,
            "implied_sub_rank_type": None,
        },
    ]
    session = _make_session_mock([_result(rows, many=True)])
    service = _make_service(_make_pool_mock(session))

    response = await service.get_all_presets_grouped()

    assert set(response.presets.keys()) == {
        RankPresetKind.bjj_belts,
        RankPresetKind.bjj_belts_stripes,
        RankPresetKind.flat,
    }
    bjj = response.presets[RankPresetKind.bjj_belts]
    assert [p.name for p in bjj] == ["White", "Blue"]

    stripes = response.presets[RankPresetKind.bjj_belts_stripes]
    assert len(stripes) == 1
    assert stripes[0].sub_rank_count == 5
    assert stripes[0].implied_sub_rank_type is SubRankType.stripes

    flat = response.presets[RankPresetKind.flat]
    assert [p.name for p in flat] == ["Member"]


# ---------- promote_member (leaf-aware) ----------


def _two_main_ladder(gym_id, *, low_subs: int = 0, high_subs: int = 0):
    """A two-rung ladder (lowest, highest) + its rank ids.

    ``low_subs`` / ``high_subs`` are each rank's ``sub_rank_count`` (0 =
    the rank is its own leaf).
    """
    low_id = str(uuid4())
    high_id = str(uuid4())
    ladder = [
        make_rank_row(
            rank_id=low_id,
            gym_id=str(gym_id),
            name="White",
            sub_rank_count=low_subs,
        ),
        make_rank_row(
            rank_id=high_id,
            gym_id=str(gym_id),
            main_rank_num_order=1,
            name="Blue",
            sub_rank_count=high_subs,
        ),
    ]
    return low_id, high_id, ladder


def _current(rank_id, sub_index, gym_id) -> MagicMock:
    """A get_member_current_rank.sql result."""
    return _result(
        {
            "current_rank_id": rank_id,
            "current_sub_index": sub_index,
            "gym_id": gym_id,
        },
    )


@pytest.mark.asyncio
async def test_promote_member_null_rank_assigns_lowest_leaf():
    """A rank-less member is promoted to the lowest rank's base leaf."""
    gym_id = uuid4()
    member_id = uuid4()
    low_id, _high_id, ladder = _two_main_ladder(gym_id)

    session = _make_session_mock(
        [
            _current(None, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    assert str(response.new_rank.rank_id) == low_id
    assert response.new_sub_index is None  # lowest is subless
    assert _params_for(session, "set_member_rank.sql")["new_rank_id"] == low_id


@pytest.mark.asyncio
async def test_promote_member_advances_to_next_main():
    """A member on the lowest (subless) rank advances to the next main."""
    gym_id = uuid4()
    member_id = uuid4()
    low_id, high_id, ladder = _two_main_ladder(gym_id)

    session = _make_session_mock(
        [
            _current(low_id, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    assert str(response.new_rank.rank_id) == high_id


@pytest.mark.asyncio
async def test_promote_member_within_main_advances_sub_index():
    """A member below the top sub-position advances within the same main,
    and the derived sub label / display name flow through (stripes)."""
    gym_id = uuid4()
    member_id = uuid4()
    # One main rank with 3 leaves (indices 0, 1, 2). Member at 0 → 1.
    rank_id = str(uuid4())
    ladder = [
        make_rank_row(
            rank_id=rank_id,
            gym_id=str(gym_id),
            name="White",
            sub_rank_count=3,
        ),
    ]

    session = _make_session_mock(
        [
            _current(rank_id, 0, gym_id),
            _result(ladder, many=True),
            _sub_type_result("stripes"),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity (sub-only promotion logs)
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    assert str(response.new_rank.rank_id) == rank_id
    assert response.new_sub_index == 1
    assert response.new_sub_label == "1 Stripe"
    assert response.new_display_name == "White · 1 Stripe"
    assert _params_for(session, "set_member_rank.sql")["new_sub_index"] == 1
    # The sub-only promotion still logs a rank_changed activity.
    assert _load("insert_rank_activity.sql") in _executed_sql_strings(session)


@pytest.mark.asyncio
async def test_promote_member_at_top_sub_advances_to_next_main_base():
    """At the top sub-position of a main, promotion crosses to the next
    main's BASE leaf (sub-index 0 when it has sub-ranks)."""
    gym_id = uuid4()
    member_id = uuid4()
    # low has 2 leaves (member at index 1 = top), high has 4 leaves.
    low_id, high_id, ladder = _two_main_ladder(gym_id, low_subs=2, high_subs=4)

    session = _make_session_mock(
        [
            _current(low_id, 1, gym_id),
            _result(ladder, many=True),
            _sub_type_result("stripes"),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    assert str(response.new_rank.rank_id) == high_id
    assert response.new_sub_index == 0  # base leaf of the next main
    assert _params_for(session, "set_member_rank.sql")["new_sub_index"] == 0


@pytest.mark.asyncio
async def test_promote_member_raises_at_top_subless_rank():
    """Promoting a member already at the highest (subless) rank raises."""
    gym_id = uuid4()
    member_id = uuid4()
    _low_id, high_id, ladder = _two_main_ladder(gym_id)

    session = _make_session_mock(
        [
            _current(high_id, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
        ],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="highest rank"):
        await service.promote_member(
            RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
        )


@pytest.mark.asyncio
async def test_promote_member_raises_at_top_main_top_sub():
    """Top main + top sub-position → ValueError('highest rank') → 409."""
    gym_id = uuid4()
    member_id = uuid4()
    # high is the top main with 2 leaves; member sits at index 1 (top sub).
    _low_id, high_id, ladder = _two_main_ladder(gym_id, low_subs=2, high_subs=2)

    session = _make_session_mock(
        [
            _current(high_id, 1, gym_id),
            _result(ladder, many=True),
            _sub_type_result("stripes"),
        ],
    )
    service = _make_service(_make_pool_mock(session))

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
    service = _make_service(_make_pool_mock(session))

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
    session = _make_session_mock([_current(None, None, other_gym)])
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="not found"):
        await service.promote_member(
            RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
        )


@pytest.mark.asyncio
async def test_promote_member_logs_activity_in_same_session():
    """The rank UPDATE and the audit activity share one committed session —
    update runs before activity."""
    gym_id = uuid4()
    member_id = uuid4()
    low_id, _high_id, ladder = _two_main_ladder(gym_id)

    session = _make_session_mock(
        [
            _current(low_id, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

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
    """Setting an explicit rank resolves the target from the gym's ladder
    and logs the change."""
    gym_id = uuid4()
    member_id = uuid4()
    old_id = str(uuid4())
    target_id = str(uuid4())
    ladder = [make_rank_row(rank_id=target_id, gym_id=str(gym_id))]

    session = _make_session_mock(
        [
            _current(old_id, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.set_member_rank(
        RankSetMemberRequest(
            gym_id=gym_id,
            member_id=member_id,
            rank_id=target_id,
        ),
    )

    assert str(response.new_rank.rank_id) == target_id
    assert _load("insert_rank_activity.sql") in _executed_sql_strings(session)


@pytest.mark.asyncio
async def test_set_member_rank_unassign_writes_null():
    """Unassigning (rank_id=None) writes NULL and never looks up a target."""
    gym_id = uuid4()
    member_id = uuid4()
    old_id = str(uuid4())

    session = _make_session_mock(
        [
            _current(old_id, None, gym_id),
            _result([], many=True),  # ladder read (target not needed)
            _sub_type_result(),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity (rank changed → logged)
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.set_member_rank(
        RankSetMemberRequest(gym_id=gym_id, member_id=member_id, rank_id=None),
    )

    assert response.new_rank is None
    sqls = _executed_sql_strings(session)
    assert _load("get_rank.sql") not in sqls  # no per-rank lookup
    assert _params_for(session, "set_member_rank.sql")["new_rank_id"] is None


@pytest.mark.asyncio
async def test_set_member_rank_404_when_target_not_in_gym_ladder():
    """A rank_id that is not one of the gym's ranks is rejected."""
    gym_id = uuid4()
    member_id = uuid4()
    target_id = str(uuid4())  # not present in the (empty) ladder

    session = _make_session_mock(
        [
            _current(None, None, gym_id),
            _result([], many=True),
            _sub_type_result(),
        ],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="Rank not found"):
        await service.set_member_rank(
            RankSetMemberRequest(
                gym_id=gym_id,
                member_id=member_id,
                rank_id=target_id,
            ),
        )


@pytest.mark.asyncio
async def test_set_member_rank_count_gt0_without_sub_index_raises():
    """A rank with sub-ranks requires a sub_index — omitting it is a 400."""
    gym_id = uuid4()
    member_id = uuid4()
    target_id = str(uuid4())
    ladder = [
        make_rank_row(rank_id=target_id, gym_id=str(gym_id), sub_rank_count=3),
    ]

    session = _make_session_mock(
        [
            _current(None, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
        ],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match=r"sub_index must be in"):
        await service.set_member_rank(
            RankSetMemberRequest(
                gym_id=gym_id,
                member_id=member_id,
                rank_id=target_id,
                sub_index=None,
            ),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_set_member_rank_count_gt0_out_of_range_raises():
    """A sub_index outside [0, count-1] is a 400."""
    gym_id = uuid4()
    member_id = uuid4()
    target_id = str(uuid4())
    ladder = [
        make_rank_row(rank_id=target_id, gym_id=str(gym_id), sub_rank_count=3),
    ]

    session = _make_session_mock(
        [
            _current(None, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
        ],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match=r"sub_index must be in"):
        await service.set_member_rank(
            RankSetMemberRequest(
                gym_id=gym_id,
                member_id=member_id,
                rank_id=target_id,
                sub_index=5,
            ),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_set_member_rank_count0_forces_sub_index_none():
    """Setting a subless rank forces current_sub_index to NULL even when a
    stray sub_index is supplied."""
    gym_id = uuid4()
    member_id = uuid4()
    target_id = str(uuid4())
    ladder = [
        make_rank_row(rank_id=target_id, gym_id=str(gym_id), sub_rank_count=0),
    ]

    session = _make_session_mock(
        [
            _current(None, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result(),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.set_member_rank(
        RankSetMemberRequest(
            gym_id=gym_id,
            member_id=member_id,
            rank_id=target_id,
            sub_index=2,
        ),
    )

    assert response.new_sub_index is None
    assert _params_for(session, "set_member_rank.sql")["new_sub_index"] is None


# ---------- reorder_ranks ----------


def _ladder_rows(gym_id, *rank_ids) -> list[dict]:
    """A gym ladder with one main-rank row per given id, in order."""
    return [
        make_rank_row(
            rank_id=str(rid),
            gym_id=str(gym_id),
            main_rank_num_order=i,
        )
        for i, rid in enumerate(rank_ids)
    ]


def _reorder_request(gym_id, *items) -> RankReorderRequest:
    """Build a reorder request from (rank_id, main_rank_num_order) tuples."""
    return RankReorderRequest(
        gym_id=gym_id,
        ranks=[
            RankReorderItem(rank_id=rid, main_rank_num_order=main)
            for rid, main in items
        ],
    )


@pytest.mark.asyncio
async def test_reorder_ranks_shifts_before_finalizing():
    """Reorder validates against the ladder, shifts every row out of the
    target space, finalizes, then re-lists — one committed session."""
    gym_id = uuid4()
    rank_a = uuid4()
    rank_b = uuid4()

    session = _make_session_mock(
        [
            _result(_ladder_rows(gym_id, rank_a, rank_b), many=True),
            _result(None),  # shift
            _result(None),  # finalize
            _result([], many=True),  # final list
            _sub_type_result(),  # response sub_rank_type
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.reorder_ranks(
        _reorder_request(gym_id, (rank_a, 1), (rank_b, 0)),
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


@pytest.mark.asyncio
async def test_reorder_ranks_rejects_unknown_rank():
    """A payload rank_id outside the gym's ladder is a ValueError — never a
    silent no-op."""
    gym_id = uuid4()
    known = uuid4()

    session = _make_session_mock(
        [_result(_ladder_rows(gym_id, known), many=True)],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="not in this gym's ladder"):
        await service.reorder_ranks(
            _reorder_request(gym_id, (known, 0), (uuid4(), 1)),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_reorder_ranks_rejects_partial_payload():
    """A payload that misses part of the ladder is a ValueError."""
    gym_id = uuid4()
    rank_a = uuid4()
    rank_b = uuid4()

    session = _make_session_mock(
        [_result(_ladder_rows(gym_id, rank_a, rank_b), many=True)],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="entire ladder"):
        await service.reorder_ranks(
            _reorder_request(gym_id, (rank_a, 0)),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_reorder_ranks_rejects_duplicate_position():
    """Two ranks aimed at the same main target is a ValueError — the
    unique-order constraint would 500 at finalize otherwise."""
    gym_id = uuid4()
    rank_a = uuid4()
    rank_b = uuid4()

    session = _make_session_mock(
        [_result(_ladder_rows(gym_id, rank_a, rank_b), many=True)],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match="Duplicate target position"):
        await service.reorder_ranks(
            _reorder_request(gym_id, (rank_a, 0), (rank_b, 0)),
        )
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_reorder_ranks_rejects_target_in_shift_space():
    """A target main order at/above the phase-1 shift offset is a
    ValueError (→400): it could collide with a still-shifted row during
    phase 2. The guard must fire before any shift/finalize runs."""
    gym_id = uuid4()
    rank_a = uuid4()

    session = _make_session_mock(
        [_result(_ladder_rows(gym_id, rank_a), many=True)],
    )
    service = _make_service(_make_pool_mock(session))

    with pytest.raises(ValueError, match=f"below {REORDER_SHIFT_OFFSET}"):
        await service.reorder_ranks(
            _reorder_request(gym_id, (rank_a, REORDER_SHIFT_OFFSET)),
        )
    session.commit.assert_not_awaited()


# ---------- 'none' sub-rank style (sub-ranks disabled gym-wide) ----------


@pytest.mark.asyncio
async def test_promote_member_none_gym_is_main_to_main():
    """On a 'none' gym every rank's EFFECTIVE sub-count is 0, so promotion
    skips straight to the next main's base leaf (NULL sub_index) even though
    the ranks STORE a sub_rank_count > 0 — the counts stay persisted, just
    dormant."""
    gym_id = uuid4()
    member_id = uuid4()
    low_id, high_id, ladder = _two_main_ladder(gym_id, low_subs=5, high_subs=5)

    session = _make_session_mock(
        [
            _current(low_id, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result("none"),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.promote_member(
        RankPromoteMemberRequest(gym_id=gym_id, member_id=member_id),
    )

    assert str(response.new_rank.rank_id) == high_id
    assert response.new_sub_index is None
    assert response.new_sub_label is None
    # No sub label on a 'none' gym — the display name is just the main name.
    assert response.new_display_name == "Blue"
    assert _params_for(session, "set_member_rank.sql")["new_sub_index"] is None


@pytest.mark.asyncio
async def test_set_member_rank_none_gym_forces_sub_index_none():
    """A 'none' gym forces current_sub_index to NULL even when the target rank
    STORES sub_rank_count > 0 and a stray sub_index is supplied (effective
    count 0 → subless-rank invariant)."""
    gym_id = uuid4()
    member_id = uuid4()
    target_id = str(uuid4())
    ladder = [
        make_rank_row(rank_id=target_id, gym_id=str(gym_id), sub_rank_count=3),
    ]

    session = _make_session_mock(
        [
            _current(None, None, gym_id),
            _result(ladder, many=True),
            _sub_type_result("none"),
            _result({"updated": True}),  # set_member_rank (row must be truthy)
            _result(None),  # insert_rank_activity
        ],
    )
    service = _make_service(_make_pool_mock(session))

    response = await service.set_member_rank(
        RankSetMemberRequest(
            gym_id=gym_id,
            member_id=member_id,
            rank_id=target_id,
            sub_index=2,
        ),
    )

    assert response.new_sub_index is None
    assert response.new_sub_label is None
    assert _params_for(session, "set_member_rank.sql")["new_sub_index"] is None


@pytest.mark.asyncio
async def test_backfill_none_gym_base_leaf_name_has_no_sub_label():
    """On a 'none' gym the lowest rank's base leaf is NULL (not 0) despite a
    stored sub_rank_count, so the derived backfill name carries no sub label."""
    gym_id = uuid4()
    lowest = make_rank_row(
        rank_id=str(uuid4()),
        gym_id=str(gym_id),
        name="White",
        sub_rank_count=4,
    )

    session = _make_session_mock(
        [
            _result(make_rank_row(rank_id=str(uuid4()), gym_id=str(gym_id))),
            _result({"gym_id": gym_id, "is_rank_enabled": True}),
            _result([lowest], many=True),  # backfill ladder read
            _sub_type_result("none"),  # gym sub_rank_type
            _result(None),  # backfill SQL
        ],
    )
    service = _make_service(_make_pool_mock(session))

    await service.create_rank(
        RankCreateRequest(
            gym_id=gym_id,
            main_rank_num_order=1,
            name="Blue",
            classes_to_next_major=10,
        ),
    )

    assert _params_for(session, "backfill_lowest_rank.sql")["new_rank_name"] == "White"


@pytest.mark.asyncio
async def test_reconcile_sub_index_for_gym_runs_reconcile_sql():
    """The gym-update edge opens its own session, runs the reconcile SQL with
    the new style, and commits."""
    gym_id = uuid4()
    session = _make_session_mock([_result(None)])
    members = RanksMembers(_make_pool_mock(session))

    await members.reconcile_sub_index_for_gym(gym_id, SubRankType.none)

    sqls = _executed_sql_strings(session)
    assert _load("reconcile_member_sub_index_for_gym.sql") in sqls
    params = _params_for(session, "reconcile_member_sub_index_for_gym.sql")
    assert params["sub_rank_type"] == "none"
    assert params["gym_id"] == str(gym_id)
    session.commit.assert_awaited_once()


# ---------- proximity sort (SQL contract) ----------


def test_ready_to_promote_sql_orders_by_percentage_descending():
    """The board sorts by PERCENTAGE complete toward the next leaf
    (proportionally closest first — a 30/40 member outranks a 1/10 member),
    with a deterministic member_id tiebreaker. NULLIF guards a 0
    denominator."""
    sql = _load("list_members_ready_to_promote.sql")
    assert "(classes_since::numeric / NULLIF(step_denominator, 0)) DESC" in sql
    assert "member_id ASC" in sql
    # The old absolute-remaining ascending sort is gone.
    assert "(step_denominator - classes_since) ASC" not in sql


def test_members_in_rank_sql_orders_by_percentage_all_members():
    """members-in-rank mirrors the ready board's percentage-descending sort
    (a 30/40 member outranks a 1/10 member) but returns EVERY member on the
    rank — no membership / top-of-ladder filter and NO step_denominator
    filter (NULL steps sort last via NULLS LAST)."""
    sql = _load("list_members_in_rank.sql")
    assert (
        "(classes_since::numeric / NULLIF(step_denominator, 0)) DESC NULLS LAST"
        in sql
    )
    assert "member_id ASC" in sql
    # The old sub-index / name sort is gone.
    assert "m.current_sub_index ASC NULLS FIRST" not in sql
    # Unlike the ready board, no rows are dropped by a step filter.
    assert "WHERE step_denominator IS NOT NULL" not in sql


# ---------- per-sub-index counts ----------


@pytest.mark.asyncio
async def test_count_members_by_sub_index_sums_total():
    """The per-sub-index breakdown is returned in order and total_count is
    the Python sum of the per-slot counts."""
    gym_id = uuid4()
    rank_id = uuid4()
    rows = [
        {"sub_index": 0, "count": 3},
        {"sub_index": 1, "count": 2},
    ]
    session = _make_session_mock([_result(rows, many=True)])
    service = _make_service(_make_pool_mock(session))

    response = await service.count_members_by_sub_index(gym_id, rank_id)

    assert response.total_count == 5
    assert [(c.sub_index, c.count) for c in response.counts] == [(0, 3), (1, 2)]

    params = _params_for(session, "count_members_by_sub_index.sql")
    assert params["gym_id"] == str(gym_id)
    assert params["rank_id"] == str(rank_id)


@pytest.mark.asyncio
async def test_count_members_by_sub_index_none_gym_single_null_row():
    """On a 'none' gym members carry a NULL sub-index, so the read returns a
    single {null, total} row and total_count is that count."""
    gym_id = uuid4()
    rank_id = uuid4()
    rows = [{"sub_index": None, "count": 7}]
    session = _make_session_mock([_result(rows, many=True)])
    service = _make_service(_make_pool_mock(session))

    response = await service.count_members_by_sub_index(gym_id, rank_id)

    assert response.total_count == 7
    assert len(response.counts) == 1
    assert response.counts[0].sub_index is None
    assert response.counts[0].count == 7
