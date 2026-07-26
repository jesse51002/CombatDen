import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/flow_segmented.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// How the first recurring period is charged, slotted INTO the money panel.
///
/// It lives here rather than on a screen of its own because the choice moves
/// the DUE TODAY figure directly above it — the old flow stranded it on a
/// separate step from the total it re-prices, so staff chose blind. The
/// panel's own proration note lands directly beneath it, which is what makes
/// the choice legible as it moves the number.
class WizardReviewFirstPeriod extends StatelessWidget {
  final ProrationBehavior value;
  final ValueChanged<ProrationBehavior> onChanged;

  const WizardReviewFirstPeriod({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        Text(WizardReviewCopy.firstPeriodEyebrow, style: scale.eyebrow),
        FlowSegmented<ProrationBehavior>(
          // The two REAL behaviours only. `ProrationBehavior.unknown` is the
          // enum's JSON fallback, never a choice anybody may be offered.
          options: const [
            ProrationBehavior.prorateToAnchor,
            ProrationBehavior.noCharge,
          ],
          value: value,
          // Half a decision each: the pair divides the panel's width rather
          // than hugging its words.
          fill: true,
          labelOf: (option) => option == ProrationBehavior.prorateToAnchor
              ? WizardReviewCopy.prorateNow
              : WizardReviewCopy.noChargeNow,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
