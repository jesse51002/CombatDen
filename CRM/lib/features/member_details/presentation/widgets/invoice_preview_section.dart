import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';

/// Fetches a `*/preview` invoice and renders it as a
/// titled [InvoiceBreakdown] card, handling the four render
/// states (loading, error, empty, populated) so every
/// preview-backed billing dialog gets the same behaviour
/// without re-wiring the fetch.
///
/// Feature-scoped on purpose: it knows the member-detail
/// [PaymentsInvoicePreviewResponse] and maps it onto the
/// shared, presentation-only [InvoiceBreakdownData]. The
/// shared widget stays decoupled from any billing model
/// (see `invoice_breakdown_data.dart`).
class InvoicePreviewSection extends StatefulWidget {
  /// Returns the preview, or `null` when the mutation has
  /// no billing impact (backend returns a null body).
  final Future<PaymentsInvoicePreviewResponse?> Function()
      loadPreview;

  /// Re-fetches the preview whenever this key changes.
  final Object? refreshKey;

  /// Heading shown above the breakdown.
  final String title;

  /// Copy shown when the mutation has no billing impact.
  final String emptyLabel;

  const InvoicePreviewSection({
    super.key,
    required this.loadPreview,
    this.refreshKey,
    this.title = 'What will be charged today',
    this.emptyLabel = 'No charge today.',
  });

  @override
  State<InvoicePreviewSection> createState() =>
      _InvoicePreviewSectionState();
}

class _InvoicePreviewSectionState
    extends State<InvoicePreviewSection> {
  late Future<PaymentsInvoicePreviewResponse?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadPreview();
  }

  @override
  void didUpdateWidget(
    covariant InvoicePreviewSection oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      setState(() {
        _future = widget.loadPreview();
      });
    }
  }

  /// Maps the backend preview onto the shared breakdown
  /// shape. Discount lines arrive inline as negative line
  /// items from Stripe, so the subtotal is only surfaced
  /// when it actually differs from the total.
  InvoiceBreakdownData _toBreakdown(
    PaymentsInvoicePreviewResponse preview,
  ) {
    return InvoiceBreakdownData(
      lines: preview.lines
          .map(
            (l) => InvoiceLineItem(
              description: l.description ?? 'Line item',
              amount: l.amount,
            ),
          )
          .toList(),
      subtotal: preview.subtotal == preview.total
          ? null
          : preview.subtotal,
      total: preview.total,
      currency: preview.currency,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(widget.title, style: DesignConstants.h3),
        Container(
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
          child: _PreviewBody(
            future: _future,
            emptyLabel: widget.emptyLabel,
            toBreakdown: _toBreakdown,
          ),
        ),
      ],
    );
  }
}

class _PreviewBody extends StatelessWidget {
  final Future<PaymentsInvoicePreviewResponse?> future;
  final String emptyLabel;
  final InvoiceBreakdownData Function(
    PaymentsInvoicePreviewResponse,
  ) toBreakdown;

  const _PreviewBody({
    required this.future,
    required this.emptyLabel,
    required this.toBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PaymentsInvoicePreviewResponse?>(
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
        final preview = snapshot.data;
        if (preview == null) {
          return Text(
            emptyLabel,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        return InvoiceBreakdown(
          data: toBreakdown(preview),
        );
      },
    );
  }
}
