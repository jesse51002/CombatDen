import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';

/// Review step — toggle proration / cash-paid and review a
/// live charge preview before confirming. The preview
/// re-fetches whenever the request (plan, prorate, cash)
/// changes.
class StartMembershipReviewStep extends StatelessWidget {
  final MemberRepository repository;
  final MemberMembershipsStartRequest? request;
  final PlanType planType;
  final bool prorate;
  final bool paidWithCash;
  final ValueChanged<bool> onProrateChanged;
  final ValueChanged<bool> onPaidWithCashChanged;

  const StartMembershipReviewStep({
    super.key,
    required this.repository,
    required this.request,
    required this.planType,
    required this.prorate,
    required this.paidWithCash,
    required this.onProrateChanged,
    required this.onPaidWithCashChanged,
  });

  @override
  Widget build(BuildContext context) {
    final req = request;
    final isRecurring = planType == PlanType.recurring;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (isRecurring)
          SwitchListTile(
            value: prorate,
            onChanged: onProrateChanged,
            activeThumbColor: DesignConstants.primaryColor,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Prorate the first charge',
              style: DesignConstants.p,
            ),
            subtitle: Text(
              'Charge only for the remainder of the '
              'current cycle.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ),
        SwitchListTile(
          value: paidWithCash,
          onChanged: onPaidWithCashChanged,
          activeThumbColor: DesignConstants.primaryColor,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Paid in cash (no card charge)',
            style: DesignConstants.p,
          ),
          subtitle: Text(
            'Record the first payment as cash; the card '
            'is not charged now.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
        if (req != null)
          InvoicePreviewSection(
            refreshKey: '${req.memberId}-${req.priceId}-'
                '$prorate-$paidWithCash',
            loadPreview: () =>
                repository.previewStartMembership(req),
          ),
      ],
    );
  }
}
