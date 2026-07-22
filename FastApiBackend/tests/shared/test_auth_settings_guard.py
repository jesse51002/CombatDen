"""Unit tests for the GoTrue auto-confirm startup guard.

The guard is fail-closed by DEFAULT, so a bug in it takes the whole app
down. These pin the four outcomes that matter: an open auth stack refuses
to boot, the explicit ``warn`` opt-out still boots, a properly-confirming
stack is silent, and an UNREACHABLE GoTrue is tolerated (a network blip
must never masquerade as a misconfiguration and cause an outage).
"""

from __future__ import annotations

import logging
from typing import Any

import httpx
import pytest

from src.core.config import AuthAutoconfirmPolicy
from src.shared.auth_settings_guard import (
    AUTOCONFIRM_KEY,
    AuthSettingsGuard,
)

_URL = "http://localhost:54321"
_KEY = "anon-key"


def _guard(policy: AuthAutoconfirmPolicy) -> AuthSettingsGuard:
    return AuthSettingsGuard(
        supabase_url=_URL,
        supabase_anon_key=_KEY,
        policy=policy,
        timeout_seconds=1.0,
    )


def _patch_probe(monkeypatch, value: bool | None) -> None:
    """Stub the settings probe with a known answer."""

    async def _fake(self) -> bool | None:
        return value

    monkeypatch.setattr(AuthSettingsGuard, "_read_autoconfirm", _fake)


# ── The load-bearing case: an open auth stack must not boot ────────


@pytest.mark.asyncio
async def test_autoconfirm_on_refuses_to_boot_by_default(monkeypatch):
    """mailer_autoconfirm=true + the DEFAULT policy => RuntimeError.

    This is the whole point of the guard: GoTrue stamps
    email_confirmed_at itself under auto-confirm, so the verified-email
    predicate proves nothing and anyone can sign up as an existing
    owner's address.
    """
    _patch_probe(monkeypatch, True)

    with pytest.raises(RuntimeError, match="Refusing to start"):
        await _guard(AuthAutoconfirmPolicy.FAIL).check()


@pytest.mark.asyncio
async def test_autoconfirm_on_with_warn_policy_boots_but_screams(
    monkeypatch, caplog
):
    """The explicit opt-out still boots — and still logs CRITICAL."""
    _patch_probe(monkeypatch, True)

    with caplog.at_level(logging.CRITICAL):
        await _guard(AuthAutoconfirmPolicy.WARN).check()

    assert any(r.levelno == logging.CRITICAL for r in caplog.records)
    assert AUTOCONFIRM_KEY in caplog.text


@pytest.mark.asyncio
async def test_confirmations_on_is_silent(monkeypatch, caplog):
    """mailer_autoconfirm=false => no raise, nothing above INFO."""
    _patch_probe(monkeypatch, False)

    with caplog.at_level(logging.INFO):
        await _guard(AuthAutoconfirmPolicy.FAIL).check()

    assert not [r for r in caplog.records if r.levelno > logging.INFO]


# ── A blip must never become an outage ─────────────────────────────


@pytest.mark.asyncio
async def test_unreachable_gotrue_is_tolerated_even_when_failing(
    monkeypatch, caplog
):
    """Unknown != misconfigured.

    The probe cannot tell an open auth stack from a network error, so
    refusing to boot here would turn a transient blip into an outage.
    """
    _patch_probe(monkeypatch, None)

    with caplog.at_level(logging.WARNING):
        await _guard(AuthAutoconfirmPolicy.FAIL).check()

    assert "UNKNOWN" in caplog.text or "Could not read" in caplog.text


@pytest.mark.asyncio
async def test_probe_returns_none_on_transport_error(monkeypatch):
    """A real httpx failure resolves to None rather than propagating."""

    async def _boom(self, *args: Any, **kwargs: Any):
        raise httpx.ConnectError("refused")

    monkeypatch.setattr(httpx.AsyncClient, "get", _boom)

    assert await _guard(AuthAutoconfirmPolicy.FAIL)._read_autoconfirm() is None


@pytest.mark.asyncio
async def test_probe_returns_none_on_missing_or_non_bool_key(monkeypatch):
    """A payload without a usable mailer_autoconfirm is 'unknowable'."""

    class _Resp:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, Any]:
            return {AUTOCONFIRM_KEY: "yes"}  # a string, not a bool

    async def _ok(self, *args: Any, **kwargs: Any) -> _Resp:
        return _Resp()

    monkeypatch.setattr(httpx.AsyncClient, "get", _ok)

    assert await _guard(AuthAutoconfirmPolicy.FAIL)._read_autoconfirm() is None
