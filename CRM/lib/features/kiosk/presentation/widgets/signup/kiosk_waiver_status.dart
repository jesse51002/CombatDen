import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The waiver step with no body on screen yet: the read is in flight, or it
/// failed and can simply be tried again.
///
/// A failed read is a retry, never a stop — see `KioskWaiverStep`. The escape
/// in the footer's left gutter remains the way out if the member wants one.
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
