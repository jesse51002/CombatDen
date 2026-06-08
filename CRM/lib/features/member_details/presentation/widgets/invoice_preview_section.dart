import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';

/// Fetches a `*/preview` invoice and renders the due-now /
/// recurring split as a titled card, handling the four
/// render states (loading, error, empty, populated) so every
/// preview-backed billing dialog gets the same behaviour
/// without re-wiring the fetch.
///
/// Both halves render through the shared [InvoiceBreakdown] so
/// the surface matches every other invoice view. The `due_now`
/// half is the breakdown "charged today". The `recurring` half is
/// captioned "Then, each month" with a `/mo` total — and when
/// [loadCurrent] is supplied it renders **comparatively**
/// (current monthly → previewed future monthly), so a start /
/// change shows "now → future" not just the new figure.
class InvoicePreviewSection extends StatefulWidget {
  /// Returns the preview, or `null` when the mutation has
  /// no billing impact (backend returns a null body).
  final Future<DueNowVsRecurringPreview?> Function()
      loadPreview;

  /// Optional: the member's current recurring invoice. When given,
  /// the recurring section is a current → new comparison. A failure
  /// or null (e.g. a brand-new member with no subscription yet) just
  /// shows the new amount with no "before".
  final Future<PreviewInvoice?> Function()? loadCurrent;

  /// Re-fetches the preview whenever this key changes.
  final Object? refreshKey;

  /// Heading shown above the breakdown.
  final String title;

  /// Copy shown when the mutation has no billing impact.
  final String emptyLabel;

  const InvoicePreviewSection({
    super.key,
    required this.loadPreview,
    this.loadCurrent,
    this.refreshKey,
    this.title = 'What will be charged today',
    this.emptyLabel = 'No charge today.',
  });

  @override
  State<InvoicePreviewSection> createState() =>
      _InvoicePreviewSectionState();
}

typedef _PreviewData = ({
  DueNowVsRecurringPreview? preview,
  PreviewInvoice? current,
});

class _InvoicePreviewSectionState
    extends State<InvoicePreviewSection> {
  late Future<_PreviewData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(
    covariant InvoicePreviewSection oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<_PreviewData> _load() async {
    final preview = await widget.loadPreview();
    PreviewInvoice? current;
    final loadCurrent = widget.loadCurrent;
    if (loadCurrent != null) {
      try {
        current = await loadCurrent();
      } catch (_) {
        // No current invoice (e.g. a new member) — show the new amount
        // with no "before". Not an error for the whole preview.
        current = null;
      }
    }
    return (preview: preview, current: current);
  }

  @override
  Widget build(BuildContext context) {
    // The title lives inside the card (above the breakdown), not as a
    // separate heading outside it.
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(widget.title, style: DesignConstants.h2),
          _PreviewBody(
            future: _future,
            emptyLabel: widget.emptyLabel,
            comparative: widget.loadCurrent != null,
          ),
        ],
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  final Future<_PreviewData> future;
  final String emptyLabel;

  /// When true the recurring half is a current → new comparison.
  final bool comparative;

  const _PreviewBody({
    required this.future,
    required this.emptyLabel,
    required this.comparative,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PreviewData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              vertical: DesignConstants.spacingMedium,
            ),
            child: Center(child: AppSpinner()),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Could not load the charge preview. You can '
            'still start the membership.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.badRed,
            ),
          );
        }
        final data = snapshot.data;
        final preview = data?.preview;
        final dueNow = preview?.dueNow;
        final recurring = preview?.recurring;
        if (dueNow == null && recurring == null) {
          return Text(
            emptyLabel,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            if (dueNow != null)
              InvoiceBreakdown(
                data: previewInvoiceBreakdown(dueNow),
              ),
            if (recurring != null)
              InvoiceBreakdown(
                data: comparative
                    ? comparisonBreakdownFromPair(
                        current: data?.current,
                        next: recurring,
                      )
                    : previewInvoiceBreakdown(
                        recurring,
                        amountSuffix: '/mo',
                      ),
                headerCaption: 'Then, each month',
                strongHeaderCaption: true,
                headerMeta: recurring.nextPaymentAt == null
                    ? null
                    : formatDay(recurring.nextPaymentAt),
              ),
          ],
        );
      },
    );
  }
}
