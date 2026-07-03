"""The shared ESIGN/UETA electronic-records consent disclosure — version pin.

US e-signature law (the federal ESIGN Act and state UETA) expects a signer to be
shown an explicit "consent to do business electronically / intent to sign"
disclosure beyond a bare agreement checkbox. Every recorded signature pins the
``esign_disclosure_version`` it was shown, so the exact wording is reproducible
from ``esign_disclosure.md`` next to this file (mirroring how ``content_hash``
reproduces the waiver text).

The backend (via ``src/shared/db_schema_path.py``) stamps only the VERSION
string onto each ``member_waiver_signatures`` row; the copy the signer actually
sees is the CRM's own hardcoded mirror (``kEsignDisclosure`` in
``CRM/lib/core/constants/esign_constants.dart``). When the legal wording
changes, all THREE move in lockstep — bump ``ESIGN_DISCLOSURE_VERSION``, update
``esign_disclosure.md`` (the version-pinned wording record), and update the CRM
constant — otherwise signers see one text while their signature pins another.
"""

# Bump in lockstep with esign_disclosure.md + the CRM's kEsignDisclosure
# whenever the wording changes.
ESIGN_DISCLOSURE_VERSION = "esign-v1"
