/// ESIGN/UETA electronic-records consent disclosure shown to signers.
///
/// PLACEHOLDER LEGAL COPY — NOT REVIEWED BY COUNSEL.
/// Replace with attorney-approved wording before relying on it in
/// production. The backend stamps the disclosure version on each
/// signature row server-side (see
/// `Database/python_data/schema/esign_disclosure.py`); the CRM only
/// displays the text, so there is no version constant to send here.
library;

const String kEsignDisclosure =
    'By typing your name and selecting Sign, you agree to the following:\n\n'
    '• You consent to use an electronic signature and to conduct this '
    'transaction electronically under the U.S. Electronic Signatures in '
    'Global and National Commerce Act (ESIGN) and applicable state Uniform '
    'Electronic Transactions Act (UETA) laws.\n\n'
    '• You intend your typed name to be your legal signature on the agreement '
    'shown above, with the same force and effect as a handwritten signature.\n\n'
    '• You confirm you are the person named, or that you are signing as the '
    'parent/legal guardian authorized to sign on that person\'s behalf.\n\n'
    '• You are able to access, view, and retain a copy of the agreement you '
    'are signing, and you may request a copy from gym staff at any time.\n\n'
    '• You may withdraw consent to transact electronically by contacting gym '
    'staff before signing; withdrawing consent does not affect the validity '
    'of signatures already made.';
