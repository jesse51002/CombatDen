import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Fetches the preview invoices and renders the shared [InvoicePreview]
/// inside a card, handling the loading / error / empty states.
///
/// The single fetch wrapper for every preview surface (membership start,
/// discount add/remove, …): [loadPreview] supplies the due-now + recurring
/// halves, and the optional [loadCurrent] supplies the recurring "before"
/// for the comparison. Set [showDueNow] false where nothing extra is
/// charged now (e.g. a discount change, whose due-now equals the recurring)
/// so it isn't shown twice.
class InvoicePreviewSection extends StatefulWidget {
  /// Returns the staged preview (due-now + recurring), or `null` when the
  /// change has no billing impact (backend returns a null body).
  final Future<DueNowVsRecurringPreview?> Function() loadPreview;

  /// Optional: the member's current recurring invoice → the comparison's
  /// "before". A failure or null (e.g. a brand-new member with no
  /// subscription yet) just shows the new amount with no "before".
  final Future<PreviewInvoice?> Function()? loadCurrent;

  /// Fallback current monthly (minor units) for the comparison when
  /// [loadCurrent] returns null.
  final int? recurringFallbackMonthly;

  /// Whether to render the due-now section.
  final bool showDueNow;

  /// Re-fetches whenever this changes.
  final Object? refreshKey;

  final String dueNowLabel;
  final String recurringLabel;
  final String emptyLabel;
  final String errorLabel;

  const InvoicePreviewSection({
    super.key,
    required this.loadPreview,
    this.loadCurrent,
    this.recurringFallbackMonthly,
    this.showDueNow = true,
    this.refreshKey,
    this.dueNowLabel = 'What will be charged today',
    this.recurringLabel = 'Then, each month',
    this.emptyLabel = 'No charge today.',
    this.errorLabel = 'Could not load the charge preview.',
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
      child: FutureBuilder<_PreviewData>(
        future: _future,
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
              widget.errorLabel,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.badRed,
              ),
            );
          }
          final data = snapshot.data;
          final preview = data?.preview;
          return InvoicePreview(
            dueNow:
                widget.showDueNow ? preview?.dueNow : null,
            recurring: preview?.recurring,
            recurringPrev: data?.current,
            recurringFallbackMonthly:
                widget.recurringFallbackMonthly,
            dueNowLabel: widget.dueNowLabel,
            recurringLabel: widget.recurringLabel,
            emptyLabel: widget.emptyLabel,
          );
        },
      ),
    );
  }
}
