/// Which of CombatDen's own emails a manual send is asking for.
///
/// Mirrors the Postgres `email_kind` enum (`../Database/python_data/schema/
/// email.py`); the backend's `MANUAL_SEND_KINDS` allowlist admits exactly
/// these two on `POST /api/v1/emails/send`. Each kind names the subject id it
/// requires — the send endpoint carries IDs only, never an address.
enum EmailKind {
  /// The staff sign-in nudge. Subject: an employee.
  staffOnboarding('staff_onboarding'),

  /// The member app invite. Subject: a member.
  memberAppInvite('member_app_invite');

  final String value;
  const EmailKind(this.value);
}
