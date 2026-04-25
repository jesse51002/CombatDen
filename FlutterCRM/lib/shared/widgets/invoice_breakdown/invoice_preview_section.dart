import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';

/// Self-contained section that fetches and renders an
/// invoice preview for a pending mutation.
///
/// Handles the four render states (loading, error, empty,
/// populated) so every preview-backed dialog gets the
/// same behaviour without duplicating state wiring.
class InvoicePreviewSection extends StatefulWidget {
  /// Returns the preview, or `null` when the mutation has
  /// no billing impact (backend returns 204 / null body).
  final Future<PaymentsInvoicePreviewResponse?> Function()
      loadPreview;

  /// Rebuilds the preview when this key changes.
  final Object? refreshKey;

  const InvoicePreviewSection({
    super.key,
    required this.loadPreview,
    this.refreshKey,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PaymentsInvoicePreviewResponse?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const _PreviewLoading();
        }
        if (snapshot.hasError) {
          return _PreviewError(
            message: snapshot.error.toString(),
          );
        }
        final preview = snapshot.data;
        if (preview == null) {
          return const _PreviewEmpty();
        }
        return InvoiceBreakdown(
          data: InvoiceBreakdownData.fromPreview(preview),
        );
      },
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingLarge,
      ),
      child: Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              DesignConstants.primaryColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  final String message;

  const _PreviewError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Could not load preview: $message',
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.badRed,
      ),
    );
  }
}

class _PreviewEmpty extends StatelessWidget {
  const _PreviewEmpty();

  @override
  Widget build(BuildContext context) {
    return Text(
      'No billing impact.',
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}
