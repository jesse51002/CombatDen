"""The shared default authorized-payer waiver — name + body text.

Both the backend (new-gym creation, via `src/shared/db_schema_path.py`) and the
`python_data` seed copy this default into each gym's own `gym_waivers` row
(`is_default = true`). The body lives in a sibling markdown file so the legal
prose is editable and diff-friendly; each gym owns and versions its copy after
the seed copy, so editing this default never re-versions existing gyms.
"""

from pathlib import Path

DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME = "Authorized Payer Agreement"

_BODY_PATH = (
    Path(__file__).resolve().parent / "default_authorized_payer_waiver.md"
)


def default_authorized_payer_waiver_body() -> str:
    """Return the shared default authorized-payer waiver body (markdown)."""
    return _BODY_PATH.read_text(encoding="utf-8")
