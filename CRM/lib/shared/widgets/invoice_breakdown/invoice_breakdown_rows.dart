part of 'invoice_breakdown.dart';

/// The optional header row: a caption on the left, an optional timestamp +
/// status chip on the right. [strongCaption] renders the caption (and the
/// meta, when it stands alone) in the strong h2 section-title style.
class _Header extends StatelessWidget {
  final String caption;
  final String? meta;
  final String? statusLabel;
  final InvoiceChipTone statusTone;
  final bool strongCaption;

  const _Header({
    required this.caption,
    required this.statusTone,
    this.meta,
    this.statusLabel,
    this.strongCaption = false,
  });

  @override
  Widget build(BuildContext context) {
    final captionStyle = strongCaption
        ? DesignConstants.h2
        : DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          );
    // The meta matches a strong caption only when it stands alone; next to
    // a status chip it stays a muted timestamp (a wide h2 date would
    // overflow the header row).
    final metaStrong = strongCaption && statusLabel == null;
    final metaStyle = metaStrong
        ? DesignConstants.h2
        : DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            caption,
            style: captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            if (meta != null) Text(meta!, style: metaStyle),
            if (statusLabel != null)
              InvoiceChip(
                label: statusLabel!,
                tone: statusTone,
              ),
          ],
        ),
      ],
    );
  }
}

/// One line: a label (left) and an amount cluster (right). The amount is a
/// plain figure unless a differing [previousAmount] makes it a before→after.
class _LineRow extends StatelessWidget {
  final String label;
  final int amount;
  final String currency;
  final bool emphasised;
  final bool muted;
  final bool indent;

  /// When non-null (and ≠ [amount]) the amount renders as a
  /// before→after cluster: struck-through [previousAmount], an
  /// arrow, then [amount]. Null → a single amount (the plain path).
  final int? previousAmount;

  /// Optional per-amount suffix, e.g. "/mo" for a recurring total.
  final String? suffix;

  const _LineRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasised = false,
    this.muted = false,
    this.indent = false,
    this.previousAmount,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    // Total/Net rows are h2-sized but regular weight, so a strong h2
    // section heading carries more weight than the total beneath it.
    final base =
        emphasised ? DesignConstants.h2Regular : DesignConstants.p;
    final color =
        muted ? DesignConstants.text2nd : DesignConstants.text;
    final style = base.copyWith(color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: indent ? DesignConstants.spacingLarge : 0,
            ),
            child: Text(
              label,
              style: style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        _AmountCluster(
          amount: amount,
          previousAmount: previousAmount,
          currency: currency,
          style: style,
          suffix: suffix,
        ),
      ],
    );
  }
}

/// The right-hand amount of a line. A single amount in the plain
/// path; a struck-through old → arrow → new cluster when a
/// [previousAmount] that differs is supplied.
class _AmountCluster extends StatelessWidget {
  final int amount;
  final int? previousAmount;
  final String currency;
  final TextStyle style;
  final String? suffix;

  const _AmountCluster({
    required this.amount,
    required this.currency,
    required this.style,
    this.previousAmount,
    this.suffix,
  });

  String _fmt(int value) =>
      '${formatMinorUnits(value, currency: currency)}${suffix ?? ''}';

  @override
  Widget build(BuildContext context) {
    final prev = previousAmount;
    if (prev == null || prev == amount) {
      return Text(_fmt(amount), style: style);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          _fmt(prev),
          style: style.copyWith(
            color: DesignConstants.text2nd,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        Text(
          '→',
          style: style.copyWith(color: DesignConstants.text2nd),
        ),
        Text(_fmt(amount), style: style),
      ],
    );
  }
}

/// The signed delta row under a comparison total: "$X more" when
/// the new total is higher, "$X less" when lower.
class _DifferenceRow extends StatelessWidget {
  final int amount;
  final String currency;

  const _DifferenceRow({
    required this.amount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final word = amount < 0 ? 'less' : 'more';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text('Difference', style: DesignConstants.p),
        ),
        Text(
          '${formatMinorUnits(amount.abs(), currency: currency)}'
          ' $word',
          style: DesignConstants.p,
        ),
      ],
    );
  }
}

/// One payment attempt row: the method + time on the left, a
/// status chip and the signed amount on the right.
class _AttemptRow extends StatelessWidget {
  final InvoiceAttemptLine attempt;
  final String currency;

  const _AttemptRow({
    required this.attempt,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                attempt.method,
                style: DesignConstants.p,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                attempt.timeLabel,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            InvoiceChip(
              label: attempt.statusLabel,
              tone: attempt.statusTone,
            ),
            Text(
              formatMinorUnits(attempt.amount, currency: currency),
              style: DesignConstants.p,
            ),
          ],
        ),
      ],
    );
  }
}
