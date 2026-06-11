import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/total_due_today_row.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/warning_message.dart';

/// Step 6 — the server-side charge preview of the fully
/// assembled request (discounts included, nothing
/// committed), rendered as TWO separate cards: the
/// consolidated one-time invoice charged today, and the
/// recurring story (the proration due now — hidden when the
/// backend returns no `due_now`, i.e. prorate is off — plus
/// the steady-state per-cycle invoice). When both cards
/// carry a charge today, a prominent notice says the card
/// is charged TWICE. Confirm = navigation only.
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
    return FutureBuilder<MemberMembershipsStartPreview>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const _PreviewPanel(
            child: SizedBox(
              height: 160,
              child: Center(child: AppSpinner()),
            ),
          );
        }
        if (snapshot.hasError) {
          return _PreviewPanel(
            child: Column(
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
            ),
          );
        }
        final preview = snapshot.data!;
        if (preview.isEmpty) {
          return _PreviewPanel(
            child: Text(
              'Nothing to charge for this request.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          );
        }
        return _PreviewCards(preview: preview);
      },
    );
  }
}

/// The two-card layout: one-time purchases (today) and the
/// recurring story, with the charged-twice notice when both
/// carry a charge today and the single combined "Total due
/// today" row at the bottom.
class _PreviewCards extends StatelessWidget {
  final MemberMembershipsStartPreview preview;

  const _PreviewCards({required this.preview});

  /// Both cards bill the card today: a non-zero one-time
  /// invoice AND a non-zero recurring amount due now — two
  /// separate charges on the payer's statement.
  bool get _chargedTwiceToday =>
      (preview.oneTime?.total ?? 0) > 0 &&
      (preview.dueNow?.total ?? 0) > 0;

  /// The one combined number charged today across both
  /// cards (one-time + recurring due now).
  int get _totalDueToday =>
      (preview.oneTime?.total ?? 0) +
      (preview.dueNow?.total ?? 0);

  String get _currency =>
      preview.oneTime?.currency ??
      preview.dueNow?.currency ??
      preview.recurring?.currency ??
      'usd';

  @override
  Widget build(BuildContext context) {
    final oneTime = preview.oneTime;
    final dueNow = preview.dueNow;
    final recurring = preview.recurring;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (_chargedTwiceToday)
          const WarningMessage(
            message: 'The card will be charged TWICE '
                'today — one charge for the one-time '
                'purchases and a separate charge for the '
                'recurring amount due now. They appear as '
                'two charges on the statement.',
          ),
        if (oneTime != null)
          _PreviewPanel(
            child: InvoiceBreakdown(
              data: previewInvoiceBreakdown(oneTime),
              headerCaption:
                  'One-time purchases (today)',
              strongHeaderCaption: true,
            ),
          ),
        if (dueNow != null || recurring != null)
          _PreviewPanel(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingLarge,
              children: [
                if (dueNow != null)
                  InvoiceBreakdown(
                    data:
                        previewInvoiceBreakdown(dueNow),
                    headerCaption: 'Due now',
                    strongHeaderCaption: true,
                  ),
                if (recurring != null)
                  InvoiceBreakdown(
                    data: previewInvoiceBreakdown(
                      recurring,
                      amountSuffix: '/cycle',
                    ),
                    headerCaption: 'Then, each cycle',
                    strongHeaderCaption: true,
                  ),
              ],
            ),
          ),
        TotalDueTodayRow(
          amount: _totalDueToday,
          currency: _currency,
        ),
      ],
    );
  }
}

/// The wizard's card chrome around one preview group — the
/// shared [SectionCard] in the step's surface treatment.
class _PreviewPanel extends StatelessWidget {
  final Widget child;

  const _PreviewPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      borderRadius: DesignConstants.radiusBig,
      backgroundColor: DesignConstants.backgroundColor,
      child: child,
    );
  }
}
