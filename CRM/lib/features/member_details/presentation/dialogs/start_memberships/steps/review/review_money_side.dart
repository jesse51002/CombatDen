import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_charges_failed.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_first_period.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_recurring_breakdown.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_views.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_money_panel.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The review's right half — the money, and only ever ONE of its four states.
///
/// The read is in flight, it failed and offers a retry, it landed with nothing
/// to charge, or it landed with a figure. Each is a different sentence about
/// the payer's card, and collapsing any two of them is how a screen ends up
/// showing `$0.00` for a price it simply does not know.
class WizardReviewMoneySide extends StatelessWidget {
  final MembershipWizardState state;
  final ValueChanged<ProrationBehavior> onProration;
  final VoidCallback onRetryPreview;

  const WizardReviewMoneySide({
    super.key,
    required this.state,
    required this.onProration,
    required this.onRetryPreview,
  });

  @override
  Widget build(BuildContext context) {
    // Everything was taken back off, so there is nothing to price and nothing
    // will be asked for. The foot says so; a spinner here would be the read
    // that never resolves this whole flow was rebuilt to end.
    if (!state.hasAnyMembership) return const SizedBox.shrink();
    if (state.previewLoad.isFailed) {
      return WizardReviewChargesFailed(onRetry: onRetryPreview);
    }
    if (!state.previewLoad.isReady) {
      return const Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: Center(child: AppSpinner()),
      );
    }
    final preview = state.preview;
    if (preview == null || preview.isEmpty) return const _NothingToCharge();
    return FlowMoneyPanel(
      money: wizardMoneyView(state),
      contactEmail: state.payerDetail?.personalInfo.email ?? '',
      // Absent, not disabled, on a cart with nothing recurring in it: there is
      // no first period to decide about.
      firstPeriod: state.hasRecurring
          ? WizardReviewFirstPeriod(
              value: state.prorationBehavior,
              onChanged: onProration,
            )
          : null,
      recurringBreakdown: WizardReviewRecurringBreakdown(state: state),
    );
  }
}

/// A landed preview with no invoice in it — every membership in the run starts
/// today at no cost. The primary stays OPEN: there is nothing to charge, which
/// is not the same as nothing to start.
class _NothingToCharge extends StatelessWidget {
  const _NothingToCharge();

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return WizardPanel(
      children: [
        Text(copy.dueTodayEyebrow, style: scale.eyebrow),
        Text(
          WizardReviewCopy.nothingToCharge,
          style: scale.body.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
