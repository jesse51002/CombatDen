"""Unit tests for the GoTrue auto-confirm startup guard.

The guard is fail-closed by DEFAULT, so a bug in it takes the whole app
down. These pin the outcomes that matter: an open auth stack refuses to
boot, a GoTrue that is reachable-but-unreadable ALSO refuses to boot under
the default policy (a reachable GoTrue is not a network blip — this closes
a fail-open), the explicit ``warn`` opt-out still boots, a properly-
confirming stack is silent, and an UNREACHABLE GoTrue is tolerated (a
network blip must never masquerade as a misconfiguration and cause an
outage).
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
    _ProbeOutcome,
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


def _patch_probe(monkeypatch, outcome: _ProbeOutcome) -> None:
    """Stub the settings probe with a known outcome."""

    async def _fake(self) -> _ProbeOutcome:
        return outcome

    monkeypatch.setattr(AuthSettingsGuard, "_probe", _fake)


def _stub_get(monkeypatch, response) -> None:
    """Stub httpx.AsyncClient.get to return a fixed response object."""

    async def _get(self, *args: Any, **kwargs: Any):
        return response

    monkeypatch.setattr(httpx.AsyncClient, "get", _get)


class _Resp:
    """A minimal httpx-response stand-in with a canned JSON body."""

    def __init__(self, body: Any) -> None:
        self._body = body

    def raise_for_status(self) -> None:
        return None

    def json(self) -> Any:
        return self._body


# ── The load-bearing cases: an unsafe/unprovable stack must not boot ──


@pytest.mark.asyncio
async def test_autoconfirm_on_refuses_to_boot_by_default(monkeypatch):
    """auto_confirming + the DEFAULT policy => RuntimeError.

    This is the whole point of the guard: GoTrue stamps
    email_confirmed_at itself under auto-confirm, so the verified-email
    predicate proves nothing and anyone can sign up as an existing
    owner's address.
    """
    _patch_probe(monkeypatch, _ProbeOutcome.auto_confirming)

    with pytest.raises(RuntimeError, match="Refusing to start"):
        await _guard(AuthAutoconfirmPolicy.FAIL).check()


@pytest.mark.asyncio
async def test_reachable_but_unreadable_refuses_to_boot_by_default(monkeypatch):
    """unreadable + the DEFAULT policy => RuntimeError.

    A GoTrue we reached but whose settings carried no readable
    mailer_autoconfirm is NOT a network blip — we cannot prove signups
    require confirmation, so under ``fail`` we refuse to serve rather than
    boot open. This closes the fail-open where a reachable-but-unparseable
    settings response booted the app even under ``fail``.
    """
    _patch_probe(monkeypatch, _ProbeOutcome.unreadable)

    with pytest.raises(RuntimeError, match="Refusing to start"):
        await _guard(AuthAutoconfirmPolicy.FAIL).check()


@pytest.mark.asyncio
async def test_autoconfirm_on_with_warn_policy_boots_but_screams(
    monkeypatch, caplog
):
    """The explicit opt-out still boots — and still logs CRITICAL."""
    _patch_probe(monkeypatch, _ProbeOutcome.auto_confirming)

    with caplog.at_level(logging.CRITICAL):
        await _guard(AuthAutoconfirmPolicy.WARN).check()

    assert any(r.levelno == logging.CRITICAL for r in caplog.records)
    assert AUTOCONFIRM_KEY in caplog.text


@pytest.mark.asyncio
async def test_unreadable_with_warn_policy_boots_but_screams(
    monkeypatch, caplog
):
    """``warn`` tolerates a reachable-but-unreadable GoTrue — booting, loudly."""
    _patch_probe(monkeypatch, _ProbeOutcome.unreadable)

    with caplog.at_level(logging.CRITICAL):
        await _guard(AuthAutoconfirmPolicy.WARN).check()

    assert any(r.levelno == logging.CRITICAL for r in caplog.records)


@pytest.mark.asyncio
async def test_confirmations_on_is_silent(monkeypatch, caplog):
    """confirmations_on => no raise, nothing above INFO."""
    _patch_probe(monkeypatch, _ProbeOutcome.confirmations_on)

    with caplog.at_level(logging.INFO):
        await _guard(AuthAutoconfirmPolicy.FAIL).check()

    assert not [r for r in caplog.records if r.levelno > logging.INFO]


# ── A blip must never become an outage ─────────────────────────────


@pytest.mark.asyncio
async def test_unreachable_gotrue_is_tolerated_even_when_failing(
    monkeypatch, caplog
):
    """Unreachable != misconfigured.

    The probe cannot tell an open auth stack from a network error, so
    refusing to boot here would turn a transient blip into an outage. No
    raise (reaching the assertions is itself the proof it did not raise).
    """
    _patch_probe(monkeypatch, _ProbeOutcome.unreachable)

    with caplog.at_level(logging.WARNING):
        await _guard(AuthAutoconfirmPolicy.FAIL).check()

    assert "UNKNOWN" in caplog.text or "Could not reach" in caplog.text


# ── _probe classification ──────────────────────────────────────────


@pytest.mark.asyncio
async def test_probe_unreachable_on_transport_error(monkeypatch):
    """A real httpx failure classifies as unreachable, never propagates."""

    async def _boom(self, *args: Any, **kwargs: Any):
        raise httpx.ConnectError("refused")

    monkeypatch.setattr(httpx.AsyncClient, "get", _boom)

    outcome = await _guard(AuthAutoconfirmPolicy.FAIL)._probe()
    assert outcome is _ProbeOutcome.unreachable


@pytest.mark.asyncio
async def test_probe_unreadable_on_non_bool_key(monkeypatch):
    """A reachable GoTrue whose flag is not a bool classifies as unreadable
    (reached, but unprovable) — NOT unreachable."""
    _stub_get(monkeypatch, _Resp({AUTOCONFIRM_KEY: "yes"}))  # a string

    outcome = await _guard(AuthAutoconfirmPolicy.FAIL)._probe()
    assert outcome is _ProbeOutcome.unreadable


@pytest.mark.asyncio
async def test_probe_unreadable_on_missing_key(monkeypatch):
    """A reachable GoTrue whose payload lacks the flag is unreadable."""
    _stub_get(monkeypatch, _Resp({"something_else": True}))

    outcome = await _guard(AuthAutoconfirmPolicy.FAIL)._probe()
    assert outcome is _ProbeOutcome.unreadable


@pytest.mark.asyncio
async def test_probe_reads_true_as_auto_confirming(monkeypatch):
    """A boolean true maps to auto_confirming."""
    _stub_get(monkeypatch, _Resp({AUTOCONFIRM_KEY: True}))

    outcome = await _guard(AuthAutoconfirmPolicy.FAIL)._probe()
    assert outcome is _ProbeOutcome.auto_confirming


@pytest.mark.asyncio
async def test_probe_reads_false_as_confirmations_on(monkeypatch):
    """A boolean false maps to confirmations_on."""
    _stub_get(monkeypatch, _Resp({AUTOCONFIRM_KEY: False}))

    outcome = await _guard(AuthAutoconfirmPolicy.FAIL)._probe()
    assert outcome is _ProbeOutcome.confirmations_on
