"""The catalog of ``{{placeholder}}`` parameters a waiver body may use.

A waiver version's ``body`` is a template that may contain ``{{key}}`` tokens; at
sign time the backend renders them from auto-filled account / gym / clock values
plus any extra ``waiver_args`` the caller supplies (the authorized-payer link
flow passes ``payee_name``). Unknown tokens render literally.

``WaiverParameter`` is the canonical key set — the single source of truth for
which placeholders exist. The backend fills them in
``WaiversSignatures._build_args`` via the enum members (never a raw string
literal); a unit test (``test_build_args_covers_the_placeholder_catalog``)
fails if the backend's filled keys drift from this catalog. The CRM mirror is
``CRM/lib/core/constants/waiver_parameters.dart`` — a hand-synced Dart copy of
the same key names (cross-language, so it can't `import` this module and must
be kept in lockstep by hand). The CRM waiver editor MUST surface every key to
the author (no invisible constants — an author can't use a placeholder they
can't see).
"""

from enum import StrEnum


class WaiverParameter(StrEnum):
    """Canonical waiver placeholder key names (mirrors the dict keys below)."""

    member_name = "member_name"
    signer_name = "signer_name"
    gym_name = "gym_name"
    date = "date"
    payee_name = "payee_name"


# Token name -> human description (shown in the CRM editor's placeholder picker).
WAIVER_PARAMETERS: dict[WaiverParameter, str] = {
    WaiverParameter.member_name: "The account holder's full name",
    WaiverParameter.signer_name: "The name typed by the person signing",
    WaiverParameter.gym_name: "The gym's name",
    WaiverParameter.date: "The date signed (YYYY-MM-DD)",
    WaiverParameter.payee_name: (
        "The member being paid for (authorized-payer waiver only)"
    ),
}
