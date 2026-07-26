import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// C5 — the people this payer covers could not be read.
///
/// The old wizard swallowed this exception and left staff on a roster step
/// that spun forever with no text and no way out. Here it says what failed,
/// that nothing has been lost, and offers the retry.
class WhoLoadFailed extends StatelessWidget {
  final String payerName;
  final VoidCallback onRetry;

  const WhoLoadFailed({
    super.key,
    required this.payerName,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return EmptyState(
      icon: Symbols.person_sharp,
      tone: EmptyStateTone.error,
      title: WizardWhoCopy.loadFailedTitle(payerName),
      body: WizardWhoCopy.loadFailedBody,
      action: AppOutlineButton(
        text: copy.retryAction,
        onPressed: onRetry,
        textStyle: scale.buttonOutlineLabel,
        borderWidth: DesignConstants.buttonBorder,
        icon: Icon(
          Symbols.refresh_sharp,
          size: DesignConstants.iconSizeSmall,
          weight: DesignConstants.iconWeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingLarge,
          vertical: DesignConstants.spacingMedium,
        ),
      ),
    );
  }
}
