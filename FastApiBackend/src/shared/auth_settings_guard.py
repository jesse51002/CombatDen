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

A failure to REACH GoTrue is NOT a misconfiguration — the check cannot tell
an open auth stack from a network blip, and refusing to boot on a blip
would make this guard an outage. It is logged as a warning and tolerated.
"""

import logging

import httpx

from src.core.config import AuthAutoconfirmPolicy

logger = logging.getLogger(__name__)

SETTINGS_PATH = "/auth/v1/settings"
AUTOCONFIRM_KEY = "mailer_autoconfirm"

_BANNER = (
    "!!! GoTrue is AUTO-CONFIRMING every signup "
    "(%s=true at %s). email_confirmed_at is stamped by GoTrue itself, so "
    "the verified-email identity model is OPEN: anyone can sign up as an "
    "existing employee's address and be admitted to that gym. Turn "
    "enable_confirmations ON for any environment holding real data."
)


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
        """Warn (or refuse to boot) when GoTrue auto-confirms signups.

        Raises:
            RuntimeError: only when auto-confirm is CONFIRMED on and the
                policy is ``fail``. Never raised for an unreachable or
                unparseable GoTrue — that is logged and tolerated.
        """
        autoconfirm = await self._read_autoconfirm()

        if autoconfirm is None:
            logger.warning(
                "Could not read GoTrue settings at %s — signup-confirmation "
                "state UNKNOWN; verify enable_confirmations manually.",
                self._settings_url,
            )
            return

        if not autoconfirm:
            logger.info(
                "GoTrue signup confirmations are ON (%s=false) — "
                "email_confirmed_at is a real proof of inbox control.",
                AUTOCONFIRM_KEY,
            )
            return

        logger.critical(_BANNER, AUTOCONFIRM_KEY, self._settings_url)
        if self._policy is AuthAutoconfirmPolicy.FAIL:
            raise RuntimeError(
                "Refusing to start: GoTrue auto-confirms signups "
                f"({AUTOCONFIRM_KEY}=true) and "
                "auth_autoconfirm_policy=fail."
            )

    async def _read_autoconfirm(self) -> bool | None:
        """Return GoTrue's ``mailer_autoconfirm``, or None if unknowable.

        None covers every "we could not find out" case — network error,
        non-2xx, non-JSON body, missing key — so the caller can separate a
        real misconfiguration from a failure to reach GoTrue.
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
                payload = response.json()
        except Exception:
            logger.warning(
                "GoTrue settings probe failed: %s",
                self._settings_url,
                exc_info=True,
            )
            return None

        value = payload.get(AUTOCONFIRM_KEY)
        return value if isinstance(value, bool) else None
