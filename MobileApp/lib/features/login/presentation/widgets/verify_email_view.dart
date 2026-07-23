import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/error_message.dart';

// The mail-hero circle diameter — a per-asset glyph frame, not a fungible
// design token (CLAUDE.md _k carve-out).
const double _kHeroDiameter = 72;

/// "Check your email" view shown after a sign-up that needs email
/// confirmation. Renders the destination [email], a resend link, and an
/// "I've confirmed, continue" primary action that re-attempts sign-in with the
/// credentials the register form still holds — the mobile flow, since the
/// confirmation link is opened in a browser and delivers no in-app session.
class VerifyEmailView extends StatelessWidget {
  const VerifyEmailView({
    super.key,
    required this.email,
    required this.isLoading,
    required this.resent,
    required this.onContinue,
    required this.onResend,
    required this.onBackToSignIn,
    this.errorMessage,
  });

  final String email;
  final bool isLoading;
  final bool resent;
  final String? errorMessage;
  final VoidCallback onContinue;
  final VoidCallback onResend;
  final VoidCallback onBackToSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: [
        const _VerifyHeader(),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            if (errorMessage != null) ErrorMessage(message: errorMessage!),
            _VerifyBody(email: email),
            if (resent) const _ResentAck(),
            AppPrimaryButton(
              text: isLoading ? 'Signing in…' : "I've confirmed, continue",
              onPressed: isLoading ? null : onContinue,
              fullWidth: true,
            ),
          ],
        ),
        _ResendLink(onResend: onResend),
        GestureDetector(
          onTap: onBackToSignIn,
          child: Text(
            'Back to sign in',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ],
    );
  }
}

/// The verify step's header: a mail glyph in a soft primary circle over the
/// title + subtitle. Leads with the mail mark (not the brand wordmark) so the
/// step instantly reads as "we sent you something, check your inbox".
class _VerifyHeader extends StatelessWidget {
  const _VerifyHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Container(
          width: _kHeroDiameter,
          height: _kHeroDiameter,
          decoration: BoxDecoration(
            color: DesignConstants.primaryCard,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Symbols.mark_email_unread_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.primaryColor,
            size: DesignConstants.iconSize2xl,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              'Check your email',
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
            Text(
              'Confirm your email to finish setting up',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }
}

/// The instruction line, with the destination email emphasized inline.
class _VerifyBody extends StatelessWidget {
  const _VerifyBody({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        children: [
          const TextSpan(text: 'We sent a confirmation link to '),
          TextSpan(
            text: email,
            style: DesignConstants.h3.copyWith(color: DesignConstants.text),
          ),
          const TextSpan(
            text: '. Open it to confirm your account, then come back and '
                'continue.',
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Inline acknowledgement shown after a successful resend.
class _ResentAck extends StatelessWidget {
  const _ResentAck();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          size: DesignConstants.iconSizeSm,
          color: DesignConstants.primaryColor,
          weight: DesignConstants.iconWeight,
        ),
        Text(
          'Confirmation link sent',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.primaryColor,
          ),
        ),
      ],
    );
  }
}

/// "Didn't get the email? Resend link".
class _ResendLink extends StatelessWidget {
  const _ResendLink({required this.onResend});

  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          "Didn't get the email?",
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        GestureDetector(
          onTap: onResend,
          child: Text(
            'Resend link',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
