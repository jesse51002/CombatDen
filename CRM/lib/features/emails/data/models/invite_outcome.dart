/// What a create / send flow actually did about the person's email.
///
/// Mirrors the backend `InviteOutcome`
/// (`../FastApiBackend/src/emails/schema/emails_schema.py`), returned on the
/// member-create, employee-create, and manual-send responses.
///
/// It exists so a confirmation can be HONEST: staff are asked whether to
/// invite, so they are told what happened rather than being shown an
/// unqualified "invite sent" for a send that never left. [unknown] is the
/// forward-compat fallback so a new backend value never crashes the UI
/// (resilient enum parsing) — and, deliberately, it never claims a send.
enum InviteOutcome {
  /// Claimed and handed to the sender — the only value that means "sent".
  queued('queued'),

  /// The kind is not enabled yet: the row records that staff asked, but
  /// nothing will go out.
  held('held'),

  /// Nobody to write to — the person has no email on file.
  skippedNoEmail('skipped_no_email'),

  /// The address unsubscribed from this gym's marketing email.
  skippedSuppressed('skipped_suppressed'),

  /// Nobody asked for an invite (created without inviting).
  notRequested('not_requested'),

  /// A value this build doesn't know. Never treated as a send.
  unknown('unknown');

  final String value;
  const InviteOutcome(this.value);

  static InviteOutcome fromJson(String value) =>
      InviteOutcome.values.firstWhere(
        (o) => o.value == value,
        orElse: () => InviteOutcome.unknown,
      );

  /// True only for [queued] — the one outcome where an email really left.
  /// Everything else must NOT be confirmed as a send.
  bool get wasSent => this == InviteOutcome.queued;

  /// The honest one-line confirmation, or null when there is nothing to say
  /// about an invite because nobody asked for one ([notRequested]).
  String? get confirmation => switch (this) {
        InviteOutcome.queued => 'Invite sent',
        InviteOutcome.held => 'Invite held — invites are off right now',
        InviteOutcome.skippedNoEmail => 'No email on file — nothing was sent',
        InviteOutcome.skippedSuppressed =>
          'That address has unsubscribed — nothing was sent',
        InviteOutcome.notRequested => null,
        InviteOutcome.unknown => "We couldn't confirm the invite was sent",
      };
}
