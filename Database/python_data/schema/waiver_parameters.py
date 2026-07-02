"""The catalog of ``{{placeholder}}`` parameters a waiver body may use.

A waiver version's ``body`` is a template that may contain ``{{key}}`` tokens; at
sign time the backend renders them from auto-filled account / gym / clock values
plus any extra ``waiver_args`` the caller supplies (the authorized-payer link
flow passes ``payee_name``). Unknown tokens render literally.

This is the single source of truth for which placeholders exist. The backend
fills them in ``WaiversSignatures.sign_waiver``; the CRM waiver editor MUST
surface them to the author (no invisible constants — an author can't use a
placeholder they can't see).
"""

# Token name -> human description (shown in the CRM editor's placeholder picker).
WAIVER_PARAMETERS: dict[str, str] = {
    "member_name": "The account holder's full name",
    "signer_name": "The name typed by the person signing",
    "gym_name": "The gym's name",
    "date": "The date signed (YYYY-MM-DD)",
    "payee_name": "The member being paid for (authorized-payer waiver only)",
}
