import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';

/// Step 5 — the server-side three-way preview of the fully
/// assembled request (discounts included, nothing
/// committed): the consolidated one-time invoice, the
/// recurring proration due now, and the steady-state
/// recurring invoice. Confirm = navigation only.
class StartPreviewStep extends StatefulWidget {
  final MemberRepository repository;
  final MemberMembershipsStartRequest request;

  /// Hands the loaded preview up so the payment step can
  /// echo the totals.
  final ValueChanged<MemberMembershipsStartPreview>
      onLoaded;

  const StartPreviewStep({
    super.key,
    required this.repository,
    required this.request,
    required this.onLoaded,
  });

  @override
  State<StartPreviewStep> createState() =>
      _StartPreviewStepState();
}

class _StartPreviewStepState
    extends State<StartPreviewStep> {
  late Future<MemberMembershipsStartPreview> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MemberMembershipsStartPreview> _load() async {
    final preview = await widget.repository
        .previewStartMemberships(widget.request);
    widget.onLoaded(preview);
    return preview;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child:
          FutureBuilder<MemberMembershipsStartPreview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState !=
              ConnectionState.done) {
            return const SizedBox(
              height: 160,
              child: Center(child: AppSpinner()),
            );
          }
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(
                  'Could not load the charge preview.',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.badRed,
                  ),
                ),
                Text(
                  '${snapshot.error}',
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            );
          }
          final preview = snapshot.data!;
          if (preview.isEmpty) {
            return Text(
              'Nothing to charge for this request.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            );
          }
          return Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              if (preview.oneTime != null)
                InvoiceBreakdown(
                  data: previewInvoiceBreakdown(
                    preview.oneTime!,
                  ),
                  headerCaption:
                      'One-time purchases (today)',
                  strongHeaderCaption: true,
                ),
              if (preview.dueNow != null)
                InvoiceBreakdown(
                  data: previewInvoiceBreakdown(
                    preview.dueNow!,
                  ),
                  headerCaption:
                      'Recurring — due now',
                  strongHeaderCaption: true,
                ),
              if (preview.recurring != null)
                InvoiceBreakdown(
                  data: previewInvoiceBreakdown(
                    preview.recurring!,
                    amountSuffix: '/cycle',
                  ),
                  headerCaption: 'Then, each cycle',
                  strongHeaderCaption: true,
                ),
            ],
          );
        },
      ),
    );
  }
}
