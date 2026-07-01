"""Regression test for C-066: MemberMembershipsCancel._mark_deleted loaded a
non-existent SQL path (src/memberships/sql/payment_sync/mark_membership_deleted.sql)
and raised FileNotFoundError, so cancelling an already-gone Stripe line 500'd.

The fix points _mark_deleted at the real file that the sync domain owns:
src/sync/sql/mark_membership_deleted.sql, binding :item_ids as a list.

Pure unit test — no DB, Stripe, or network (the db session is mocked).
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.memberships import SQL_DIR as MEMBERSHIPS_SQL_DIR
from src.memberships.service.memberships_cancel import (
    SYNC_SQL_DIR,
    MemberMembershipsCancel,
)


def test_old_broken_path_does_not_exist() -> None:
    """The path the buggy code resolved to never existed on disk."""
    broken = MEMBERSHIPS_SQL_DIR / "payment_sync" / "mark_membership_deleted.sql"
    assert not broken.exists()


def test_sync_sql_path_exists() -> None:
    """The fixed path (sync domain's SQL file) exists and binds :item_ids."""
    fixed = SYNC_SQL_DIR / "mark_membership_deleted.sql"
    assert fixed.exists()
    assert ":item_ids" in fixed.read_text()


def _fake_session(execute_mock: AsyncMock) -> object:
    """An async-context-manager session whose execute/commit are mocked."""

    class _Session:
        execute = execute_mock
        commit = AsyncMock()

        async def __aenter__(self) -> "_Session":
            return self

        async def __aexit__(self, *exc: object) -> bool:
            return False

    return _Session()


@pytest.mark.asyncio
async def test_mark_deleted_loads_existing_sql_and_binds_item_ids_list() -> None:
    """_mark_deleted resolves a real SQL file (no FileNotFoundError) and binds
    :item_ids as a single-element list for the given item_id."""
    execute_mock = AsyncMock()
    db_pool = MagicMock()
    db_pool.session = MagicMock(return_value=_fake_session(execute_mock))

    svc = MemberMembershipsCancel.__new__(MemberMembershipsCancel)
    svc._db_pool = db_pool

    item_id = uuid4()
    # Would raise FileNotFoundError before the fix.
    await svc._mark_deleted(item_id)

    execute_mock.assert_awaited_once()
    _, params = execute_mock.await_args.args
    assert params == {"item_ids": [str(item_id)]}
