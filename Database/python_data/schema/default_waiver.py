"""The shared default waiver documents — names + body text.

Both the backend (new-gym creation, via `src/shared/db_schema_path.py`) and the
`python_data` seed copy the authorized-payer default into each gym's own
`gym_waivers` row (`waiver_type = 'payer_auth'`). The seed additionally copies
the liability default into a normal `custom` waiver per gym. The bodies live in
sibling markdown files so the legal prose is editable and diff-friendly; each
gym owns and versions its copy after the seed copy, so editing a default never
re-versions existing gyms.
"""

from pathlib import Path

DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME = "Authorized Payer Agreement"
DEFAULT_LIABILITY_WAIVER_NAME = "Liability Waiver"

_PAYER_AUTH_BODY_PATH = (
    Path(__file__).resolve().parent / "default_authorized_payer_waiver.md"
)
_LIABILITY_BODY_PATH = (
    Path(__file__).resolve().parent / "default_liability_waiver.md"
)


def default_authorized_payer_waiver_body() -> str:
    """Return the shared default authorized-payer waiver body (markdown)."""
    return _PAYER_AUTH_BODY_PATH.read_text(encoding="utf-8")


def default_liability_waiver_body() -> str:
    """Return the shared default liability waiver body (markdown)."""
    return _LIABILITY_BODY_PATH.read_text(encoding="utf-8")
