import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';

/// Previews a discount add/remove as a **current → new** comparison,
/// rendered through the shared [InvoiceBreakdown] so it matches every
/// other invoice surface.
///
/// Loads the member's current recurring invoice ([loadCurrent]) and the
/// staged-change preview ([loadPreview]); `comparisonBreakdownFromPair`
/// turns the pair into a before→after breakdown — undiscounted price,
/// the discount, the line net old → new, and the Monthly total old → new
/// with a Difference row.
class DiscountChangePreview extends StatefulWidget {
  final Future<PreviewInvoice?> Function() loadCurrent;
  final Future<DueNowVsRecurringPreview?> Function() loadPreview;
  final String title;

  /// Fallback current monthly (minor units) when the current invoice
  /// can't be loaded (e.g. no live subscription yet).
  final int? fallbackCurrentMonthly;

  const DiscountChangePreview({
    super.key,
    required this.loadCurrent,
    required this.loadPreview,
    required this.title,
    this.fallbackCurrentMonthly,
  });

  @override
  State<DiscountChangePreview> createState() =>
      _DiscountChangePreviewState();
}

typedef _Pair = ({PreviewInvoice? current, PreviewInvoice? next});

class _DiscountChangePreviewState
    extends State<DiscountChangePreview> {
  late Future<_Pair> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Pair> _load() async {
    final current = await widget.loadCurrent();
    final wrap = await widget.loadPreview();
    return (current: current, next: wrap?.recurring);
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
            border: Border.all(color: DesignConstants.divider),
          ),
          child: FutureBuilder<_Pair>(
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
                  'Could not load the preview.',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.badRed,
                  ),
                );
              }
              final next = snapshot.data?.next;
              if (next == null) {
                return Text(
                  'No billing change.',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                );
              }
              return InvoiceBreakdown(
                data: comparisonBreakdownFromPair(
                  current: snapshot.data?.current,
                  next: next,
                  fallbackCurrentMonthly:
                      widget.fallbackCurrentMonthly,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
