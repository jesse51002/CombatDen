import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Previews a discount add/remove as a **current → new** comparison.
///
/// Loads the member's current recurring invoice ([loadCurrent]) and the
/// staged-change preview ([loadPreview]) — both [PreviewInvoice]s with
/// lines keyed by `stripe_subscription_item_id` — then renders an aligned
/// table: per line `label ×N  $current → $new` and a Monthly
/// `$current/mo → $new/mo` row. **Both sides are post-discount**, so the
/// per-line deltas reconcile with the monthly delta (unlike a
/// list-price → discounted view, where the line discounts dwarf the
/// actual change).
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
              return _Comparison(
                current: snapshot.data?.current,
                next: next,
                fallbackCurrentMonthly:
                    widget.fallbackCurrentMonthly,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Comparison extends StatelessWidget {
  final PreviewInvoice? current;
  final PreviewInvoice next;
  final int? fallbackCurrentMonthly;

  const _Comparison({
    required this.current,
    required this.next,
    this.fallbackCurrentMonthly,
  });

  static const _gap = EdgeInsets.only(
    left: DesignConstants.spacingMedium,
  );
  static const _rowPad = EdgeInsets.symmetric(
    vertical: DesignConstants.spacingSmall,
  );
  static const _topGap = EdgeInsets.only(
    top: DesignConstants.spacingSmall,
  );

  @override
  Widget build(BuildContext context) {
    final currency = next.currency;
    final muted = DesignConstants.text2nd;

    // Current post-discount line totals, keyed by sub-item.
    final currentBySi = <String, int>{
      for (final l in current?.lines ??
          const <PreviewInvoiceLine>[])
        if (l.stripeSubscriptionItemId != null)
          l.stripeSubscriptionItemId!: l.discountedAmount,
    };

    final rows = <TableRow>[];
    for (final l in next.lines) {
      final qty = l.quantity;
      final label = (qty != null && qty > 1)
          ? '${l.description ?? 'Line item'}  ×$qty'
          : (l.description ?? 'Line item');
      final newAmt = l.discountedAmount;
      // Fallback to the list amount only when there's no current line
      // (e.g. current invoice unavailable).
      final curAmt =
          currentBySi[l.stripeSubscriptionItemId] ?? l.amount;
      final changed = curAmt != newAmt;
      rows.add(
        TableRow(
          children: [
            Padding(
              padding: _rowPad,
              child: Text(
                label,
                style: DesignConstants.p,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _amount(
              changed
                  ? formatMinorUnits(curAmt, currency: currency)
                  : null,
              style: DesignConstants.p.copyWith(
                color: muted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            _arrow(show: changed, style: DesignConstants.p),
            _amount(
              formatMinorUnits(newAmt, currency: currency),
              style: DesignConstants.p,
            ),
          ],
        ),
      );
    }

    final curTotal = current?.total ?? fallbackCurrentMonthly;
    final newTotal = next.total;
    final totalChanged = curTotal != null && curTotal != newTotal;
    rows.add(
      TableRow(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: DesignConstants.divider),
          ),
        ),
        children: [
          Padding(
            padding: _rowPad.add(_topGap),
            child: Text('Monthly', style: DesignConstants.h2),
          ),
          _amount(
            totalChanged
                ? '${formatMinorUnits(curTotal, currency: currency)}/mo'
                : null,
            style: DesignConstants.pSmall.copyWith(
              color: muted,
              decoration: TextDecoration.lineThrough,
            ),
            topGap: true,
          ),
          _arrow(
            show: totalChanged,
            style: DesignConstants.pSmall,
            topGap: true,
          ),
          _amount(
            '${formatMinorUnits(newTotal, currency: currency)}/mo',
            style: DesignConstants.h2,
            topGap: true,
          ),
        ],
      ),
    );

    final diff = curTotal != null ? newTotal - curTotal : null;
    if (diff != null && diff != 0) {
      final less = diff < 0;
      rows.add(
        TableRow(
          children: [
            Padding(
              padding: _rowPad,
              child: Text(
                'Difference',
                style: DesignConstants.p,
              ),
            ),
            _amount(null, style: DesignConstants.p),
            _arrow(show: false, style: DesignConstants.p),
            _amount(
              '${formatMinorUnits(diff.abs(), currency: currency)}'
              ' ${less ? 'less' : 'more'}',
              style: DesignConstants.p,
            ),
          ],
        ),
      );
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment:
          TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  EdgeInsetsGeometry _cellPad(bool topGap) =>
      topGap ? _gap.add(_rowPad).add(_topGap) : _gap.add(_rowPad);

  Widget _amount(
    String? text, {
    required TextStyle style,
    bool topGap = false,
  }) {
    return Padding(
      padding: _cellPad(topGap),
      child: text == null
          ? const SizedBox.shrink()
          : Text(
              text,
              textAlign: TextAlign.right,
              style: style,
            ),
    );
  }

  Widget _arrow({
    required bool show,
    required TextStyle style,
    bool topGap = false,
  }) {
    return Padding(
      padding: _cellPad(topGap),
      child: show
          ? Text(
              '→',
              style: style.copyWith(
                color: DesignConstants.text2nd,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
