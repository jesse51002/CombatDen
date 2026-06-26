"""The reconciler's InvoiceFetchSweep delegates to the memberships fetch.

Locks in the dependency direction: the fetch+apply engine lives in
``memberships`` and the reconciler calls IN (per gym, full-account sweep —
``customer=None``). The reconciler no longer owns the fetch loop.
"""

from unittest.mock import AsyncMock
from uuid import uuid4

from src.reconciler.service.reconciler.reconciler_invoice_fetch_sweep import (
    InvoiceFetchSweep,
)


async def test_run_delegates_to_memberships_fetch_per_gym():
    invoice_fetch = AsyncMock()
    sweep = InvoiceFetchSweep(db_pool=AsyncMock(), invoice_fetch=invoice_fetch)

    gyms = [
        {"gym_id": uuid4(), "stripe_account_id": "acct_1"},
        {"gym_id": uuid4(), "stripe_account_id": "acct_2"},
    ]
    sweep._list_gyms = AsyncMock(return_value=gyms)

    result = await sweep.run()

    # One delegated full-account sweep per gym; no customer filter.
    assert invoice_fetch.sweep_account.await_count == 2
    for call, gym in zip(
        invoice_fetch.sweep_account.await_args_list, gyms, strict=True
    ):
        assert call.args[0] == gym["gym_id"]
        assert call.args[1] == gym["stripe_account_id"]
        # cutoff is a positive epoch; result accumulator is threaded through.
        assert call.args[2] > 0
        assert "customer" not in call.kwargs
    assert result.name == "invoice_fetch"
