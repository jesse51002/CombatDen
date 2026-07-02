"""The shared ESIGN/UETA electronic-records consent disclosure — version + text.

US e-signature law (the federal ESIGN Act and state UETA) expects a signer to be
shown an explicit "consent to do business electronically / intent to sign"
disclosure beyond a bare agreement checkbox. Every recorded signature pins the
``esign_disclosure_version`` it was shown, so the exact wording is reproducible
from this constant (mirroring how ``content_hash`` reproduces the waiver text).

Both the backend (via ``src/shared/db_schema_path.py``, stamped onto each
``member_waiver_signatures`` row) and the CRM (which renders the disclosure above
the sign action) read from here, so the disclosure stays a single source of truth.

Bump ``ESIGN_DISCLOSURE_VERSION`` and the markdown together whenever the legal
wording changes; old signatures keep pointing at the version they actually saw.
"""

from pathlib import Path

# Bump in lockstep with esign_disclosure.md when the wording changes.
ESIGN_DISCLOSURE_VERSION = "esign-v1"

_TEXT_PATH = Path(__file__).resolve().parent / "esign_disclosure.md"


def esign_disclosure_text() -> str:
    """Return the current ESIGN/UETA electronic-records disclosure (markdown)."""
    return _TEXT_PATH.read_text(encoding="utf-8")
