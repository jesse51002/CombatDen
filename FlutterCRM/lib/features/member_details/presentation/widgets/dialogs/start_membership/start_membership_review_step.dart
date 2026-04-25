import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_preview_section.dart';

/// Step 3 — review the invoice preview and toggle
/// proration / cash-paid options before confirming.
class StartMembershipReviewStep extends StatelessWidget {
  final MemberMembershipsStartRequest? request;
  final PlanType planType;
  final bool prorate;
  final bool paidWithCash;
  final ValueChanged<bool> onProrateChanged;
  final ValueChanged<bool> onPaidWithCashChanged;

  const StartMembershipReviewStep({
    super.key,
    required this.request,
    required this.planType,
    required this.prorate,
    required this.paidWithCash,
    required this.onProrateChanged,
    required this.onPaidWithCashChanged,
  });

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MemberRepository>();
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
              'Prorate first charge',
              style: DesignConstants.p,
            ),
          ),
        SwitchListTile(
          value: paidWithCash,
          onChanged: onPaidWithCashChanged,
          activeThumbColor: DesignConstants.primaryColor,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Paid with cash (no card charge)',
            style: DesignConstants.p,
          ),
        ),
        if (request != null)
          InvoicePreviewSection(
            refreshKey:
                '${request!.crmUserId}-${request!.priceId}-$prorate-$paidWithCash',
            loadPreview: () => repository
                .previewStartMembership(request!),
          ),
      ],
    );
  }
}
