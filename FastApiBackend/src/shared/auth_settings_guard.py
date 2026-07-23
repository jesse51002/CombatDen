"""Startup guard on GoTrue's signup-confirmation setting.

Identity in this backend is the VERIFIED email claim (see
``src/shared/auth.py``), and every identity-resolving query proves
"verified" with ``auth.users.email_confirmed_at IS NOT NULL``. That column
is only meaningful while GoTrue actually mails a confirmation: with
``enable_confirmations`` OFF, **GoTrue stamps ``email_confirmed_at`` itself
at signup**, so the DB predicate passes for an inbox nobody ever proved
control of and the whole identity model is open.

The DB cannot detect this — but GoTrue publishes its own config at
``GET {supabase_url}/auth/v1/settings`` (only the ``apikey`` header needed),
where ``mailer_autoconfirm`` is exactly that setting. This guard reads it
once at startup.

The default policy is ``fail``: it logs a CRITICAL banner and refuses to
boot, because an auth stack that auto-confirms leaves the identity model
open and that is not a state to start serving in. ``config.toml`` ships
``enable_confirmations = true``, so a correctly-started local stack passes;
tripping this means the running stack predates that setting and needs
``supabase stop && supabase start`` (the config is read at container start,
NOT by ``supabase db reset``). ``auth_autoconfirm_policy=warn`` is the
explicit opt-out for a throwaway environment holding no real data.

Reachability and readability are kept separate:

* A failure to REACH GoTrue is NOT a misconfiguration — the check cannot
  tell an open auth stack from a network blip, and refusing to boot on a
  blip would make this guard an outage. It is logged as a warning and
  tolerated, always.
* A GoTrue we DID reach whose settings carry no readable
  ``mailer_autoconfirm`` is a different case: it is not a blip, and we
  cannot prove confirmations are on, so under the ``fail`` policy it is
  fail-closed exactly like a confirmed auto-confirm. (Lumping this in with
  "unreachable" was a fail-open: a reachable-but-unparseable settings
  response booted the app even under ``fail``.)
"""

import logging
from enum import StrEnum

import httpx

from src.core.config import AuthAutoconfirmPolicy

logger = logging.getLogger(__name__)

SETTINGS_PATH = "/auth/v1/settings"
AUTOCONFIRM_KEY = "mailer_autoconfirm"

_OPEN_BANNER = (
    "!!! GoTrue is AUTO-CONFIRMING every signup "
    "(%s=true at %s). email_confirmed_at is stamped by GoTrue itself, so "
    "the verified-email identity model is OPEN: anyone can sign up as an "
    "existing employee's address and be admitted to that gym. Turn "
    "enable_confirmations ON for any environment holding real data."
)

_UNREADABLE_BANNER = (
    "!!! Reached GoTrue at %s but its settings carried no readable %s flag, "
    "so it cannot be proven that signups require email confirmation. "
    "Treating as UNSAFE — a reachable GoTrue is not a network blip. Verify "
    "enable_confirmations and GoTrue's /settings response."
)


class _ProbeOutcome(StrEnum):
    """The result of reading GoTrue's published settings once."""

    confirmations_on = "confirmations_on"  # mailer_autoconfirm=false — safe
    auto_confirming = "auto_confirming"  # mailer_autoconfirm=true — OPEN
    unreachable = "unreachable"  # could not reach GoTrue — a tolerable blip
    unreadable = "unreadable"  # reached, no readable flag — unsafe


class AuthSettingsGuard:
    """Reads GoTrue's published config once at startup and rules on it."""

    def __init__(
        self,
        supabase_url: str,
        supabase_anon_key: str,
        policy: AuthAutoconfirmPolicy,
        timeout_seconds: float,
    ) -> None:
        self._settings_url = f"{supabase_url.rstrip('/')}{SETTINGS_PATH}"
        self._anon_key = supabase_anon_key
        self._policy = policy
        self._timeout_seconds = timeout_seconds

    async def check(self) -> None:
        """Warn (or refuse to boot) unless GoTrue is proven to confirm signups.

        Raises:
            RuntimeError: under the ``fail`` policy, when GoTrue is reachable
                and EITHER auto-confirms OR gives no readable
                ``mailer_autoconfirm`` (both are unsafe to serve blindly). An
                UNREACHABLE GoTrue is logged and tolerated — never raised.
        """
        outcome = await self._probe()

        if outcome is _ProbeOutcome.confirmations_on:
            logger.info(
                "GoTrue signup confirmations are ON (%s=false) — "
                "email_confirmed_at is a real proof of inbox control.",
                AUTOCONFIRM_KEY,
            )
            return

        if outcome is _ProbeOutcome.unreachable:
            # A network blip / GoTrue not ready. The probe cannot tell an open
            # auth stack from a blip, and refusing to boot on a blip would make
            # this guard an outage — so an unreachable probe is tolerated.
            logger.warning(
                "Could not reach GoTrue settings at %s — signup-confirmation "
                "state UNKNOWN; verify enable_confirmations manually.",
                self._settings_url,
            )
            return

        # Reached GoTrue and could NOT prove confirmations are on — it either
        # auto-confirms or gave no readable flag. Neither is a blip; under the
        # fail policy, refuse to boot.
        if outcome is _ProbeOutcome.auto_confirming:
            logger.critical(_OPEN_BANNER, AUTOCONFIRM_KEY, self._settings_url)
            reason = f"GoTrue auto-confirms signups ({AUTOCONFIRM_KEY}=true)"
        else:  # unreadable
            logger.critical(
                _UNREADABLE_BANNER, self._settings_url, AUTOCONFIRM_KEY
            )
            reason = (
                f"GoTrue gave no readable {AUTOCONFIRM_KEY}, so signup "
                "confirmations cannot be verified"
            )

        if self._policy is AuthAutoconfirmPolicy.FAIL:
            raise RuntimeError(
                f"Refusing to start: {reason} and auth_autoconfirm_policy=fail."
            )

    async def _probe(self) -> _ProbeOutcome:
        """Read GoTrue's ``mailer_autoconfirm`` once, classifying the outcome.

        Reachability (the network GET + a 2xx) is kept separate from
        readability (a JSON body carrying a boolean ``mailer_autoconfirm``):
        an unreachable GoTrue is a tolerable blip, but a reachable one whose
        settings we cannot read is unsafe, not merely unknown.
        """
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout_seconds
            ) as client:
                response = await client.get(
                    self._settings_url,
                    headers={"apikey": self._anon_key},
                )
                response.raise_for_status()
        except Exception:
            logger.warning(
                "GoTrue settings probe could not reach %s",
                self._settings_url,
                exc_info=True,
            )
            return _ProbeOutcome.unreachable

        # Reached GoTrue (2xx). From here a bad body / missing-or-non-bool flag
        # is UNREADABLE, not unreachable — we did reach it.
        try:
            payload = response.json()
            value = payload.get(AUTOCONFIRM_KEY)
        except Exception:
            value = None

        if not isinstance(value, bool):
            return _ProbeOutcome.unreadable
        return (
            _ProbeOutcome.auto_confirming
            if value
            else _ProbeOutcome.confirmations_on
        )
