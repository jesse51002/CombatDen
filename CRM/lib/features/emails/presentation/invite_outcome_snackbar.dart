import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';

/// Surfaces an [InviteOutcome] as the app's standard snackbar — green only for
/// [InviteOutcome.queued] (the one outcome where an email really left), amber
/// for every honest not-sent answer.
///
/// [InviteOutcome.notRequested] has nothing to say about an invite, so it
/// shows nothing at all rather than a confusing empty toast.
void showInviteOutcomeSnackBar(
  BuildContext context,
  InviteOutcome outcome,
) {
  final message = outcome.confirmation;
  if (message == null) return;
  final fill = outcome.wasSent
      ? DesignConstants.goodGreen
      : DesignConstants.okYellow;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.onFill(fill),
          ),
        ),
        backgroundColor: fill,
      ),
    );
}

/// Surfaces a failed send. The backend's per-subject hourly cap gets its own
/// plain-language message ([InviteRateLimitedException]) rather than a generic
/// server error, because "we already sent three of these" is a real answer the
/// staff member can act on.
void showInviteErrorSnackBar(BuildContext context, Object error) {
  final message = switch (error) {
    InviteRateLimitedException() =>
      'Too many invites sent — try again later.',
    ServerException(:final detail, :final message) => detail ?? message,
    _ => "We couldn't send that invite. Please try again.",
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.onFill(DesignConstants.badRed),
          ),
        ),
        backgroundColor: DesignConstants.badRed,
      ),
    );
}
