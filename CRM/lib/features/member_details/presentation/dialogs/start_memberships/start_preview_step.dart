import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
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

  /// The payer's current monthly recurring total (minor units) —
  /// the "before" baseline for the recurring before→after. When
  /// 0/absent the payer has no live subscription, so the
  /// recurring card stays a plain (non-comparison) view.
  final int? currentMonthly;

  /// Hands the loaded preview up so the payment step can
  /// echo the totals.
  final ValueChanged<MemberMembershipsStartPreview>
      onLoaded;

  const StartPreviewStep({
    super.key,
    required this.repository,
    required this.request,
    required this.onLoaded,
    this.currentMonthly,
  });

  @override
  State<StartPreviewStep> createState() =>
      _StartPreviewStepState();
}

class _StartPreviewStepState
    extends State<StartPreviewStep> {
  late Future<_PreviewData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PreviewData> _load() async {
    final preview = await widget.repository
        .previewStartMemberships(widget.request);
    widget.onLoaded(preview);
    // Only a payer with a live subscription has a "before"
    // recurring invoice to compare against; a fresh payer is
    // starting from nothing, so we skip the fetch and the
    // recurring card stays the plain new-cycle view.
    PreviewInvoice? current;
    if ((widget.currentMonthly ?? 0) > 0) {
      try {
        current = await widget.repository
            .getUpcomingInvoice(widget.request.payerMemberId);
      } catch (_) {
        // No reachable current invoice — fall back to the
        // monthly total for a total-only before→after.
        current = null;
      }
    }
    return _PreviewData(preview: preview, current: current);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PreviewData>(
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
        final data = snapshot.data!;
        final preview = data.preview;
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
        return _PreviewCards(
          preview: preview,
          currentRecurring: data.current,
          fallbackCurrentMonthly: widget.currentMonthly,
        );
      },
    );
  }
}

/// The start preview plus the payer's current recurring invoice
/// (the "before" baseline), loaded together so the recurring
/// card can render a before→after.
class _PreviewData {
  final MemberMembershipsStartPreview preview;
  final PreviewInvoice? current;

  const _PreviewData({required this.preview, this.current});
}

/// The two-card layout: one-time purchases (today) and the
/// recurring story, with the charged-twice notice when both
/// carry a charge today and the single combined "Total due
/// today" row at the bottom.
class _PreviewCards extends StatelessWidget {
  final MemberMembershipsStartPreview preview;

  /// The payer's current recurring invoice (the "before"), and a
  /// monthly-total fallback. When either is present the recurring
  /// card renders the new cycle as a current → new comparison.
  final PreviewInvoice? currentRecurring;
  final int? fallbackCurrentMonthly;

  const _PreviewCards({
    required this.preview,
    this.currentRecurring,
    this.fallbackCurrentMonthly,
  });

  bool get _comparativeRecurring =>
      currentRecurring != null ||
      (fallbackCurrentMonthly ?? 0) > 0;

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
                    data: _comparativeRecurring
                        ? comparisonBreakdownFromPair(
                            current: currentRecurring,
                            next: recurring,
                            fallbackCurrentMonthly:
                                fallbackCurrentMonthly,
                            totalLabel: 'Total',
                            amountSuffix: '/cycle',
                          )
                        : previewInvoiceBreakdown(
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
