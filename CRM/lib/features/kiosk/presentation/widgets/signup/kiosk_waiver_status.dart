import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The waiver step with no body on screen yet: the read is in flight, or it
/// failed and can simply be tried again.
///
/// **A failed read is never a stop here.** A member row and a Stripe customer
/// already exist by this point, so ending the signup over one flaky call would
/// orphan them; the escape in the footer's left gutter remains the way out if
/// the member does want one.
class KioskWaiverStatus extends StatelessWidget {
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  const KioskWaiverStatus({
    super.key,
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: loading || !failed
            ? const AppSpinner()
            : Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  Text(
                    'We couldn\'t load the waiver just now.',
                    style: DesignConstants.kioskSubtitle.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  KioskPrimaryButton(text: 'Try again', onPressed: onRetry),
                ],
              ),
      ),
    );
  }
}

/// A one-line notice above the waiver — the republished-version warning, and
/// the inline "that didn't go through" after a failed sign.
///
/// It wears the warm stop palette rather than the red one: neither of these is
/// the member's mistake, and neither is a dead end.
class KioskWaiverNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const KioskWaiverNotice({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.info_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.okYellow,
          ),
          Expanded(
            child: Text(message, style: DesignConstants.kioskBody),
          ),
          if (retry != null)
            KioskOutlineButton(text: 'Try again', onPressed: retry),
        ],
      ),
    );
  }
}
