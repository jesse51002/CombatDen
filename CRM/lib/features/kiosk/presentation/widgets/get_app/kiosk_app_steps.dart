import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The two numbered sign-in steps under the download QR.
///
/// Step 2 shows the member's own address as a mono chip ONLY when the kiosk
/// actually knows it ([memberEmail] non-empty) — i.e. after a check-in, where
/// the modal opened off the glance. Opened from the idle home there is no
/// member yet, so the step renders without an address rather than showing a
/// stand-in one: a member-facing kiosk must never display an email that is not
/// theirs.
class KioskAppSteps extends StatelessWidget {
  final String? memberEmail;

  const KioskAppSteps({super.key, this.memberEmail});

  @override
  Widget build(BuildContext context) {
    final email = memberEmail;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const _Step(number: 1, label: 'Scan to download the app'),
        _Step(
          number: 2,
          label: 'Sign in with the email you signed up with',
          email: (email != null && email.isNotEmpty) ? email : null,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String label;
  final String? email;

  const _Step({required this.number, required this.label, this.email});

  @override
  Widget build(BuildContext context) {
    final address = email;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        _StepNumber(number: number),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(label, style: DesignConstants.kioskCaption),
              if (address != null) _EmailChip(email: address),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small filled sapphire disc carrying the step number.
class _StepNumber extends StatelessWidget {
  final int number;

  const _StepNumber({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.iconSizeLarge,
      height: DesignConstants.iconSizeLarge,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: DesignConstants.kioskMicro.copyWith(
          color: DesignConstants.onAccent,
        ),
      ),
    );
  }
}

/// The member's own sign-in address, set apart as a mono chip so it reads as
/// a literal value to copy, not prose.
class _EmailChip extends StatelessWidget {
  final String email;

  const _EmailChip({required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: DesignConstants.primaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        email,
        style: DesignConstants.kioskMonoValue.copyWith(
          color: DesignConstants.accentDark,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
