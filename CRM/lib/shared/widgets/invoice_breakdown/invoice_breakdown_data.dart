import 'package:equatable/equatable.dart';

import 'package:crm/shared/widgets/invoice_breakdown/invoice_attempt_line.dart';

/// One line on an invoice breakdown: a label and a signed
/// amount in minor currency units (cents for USD).
///
/// Two optional fields turn a plain line into a before/after
/// comparison line. When both are null (every plain surface)
/// the line renders exactly as a single amount.
class InvoiceLineItem extends Equatable {
  final String description;

  /// In plain mode the single amount shown. In comparison mode the
  /// **undiscounted (list) price**; the new net is [amount] +
  /// [discountAmount].
  final int amount;

  /// Optional aggregate discount on this line (signed, negative).
  /// When set, the widget renders an indented muted "Discount" row
  /// beneath the line.
  final int? discountAmount;

  /// Optional **prior net** for a before→after comparison. When set
  /// (and ≠ the new net), the widget renders the line's net
  /// old → new beneath the line.
  final int? previousAmount;

  const InvoiceLineItem({
    required this.description,
    required this.amount,
    this.discountAmount,
    this.previousAmount,
  });

  @override
  List<Object?> get props =>
      [description, amount, discountAmount, previousAmount];
}

/// One applied-discount line on an invoice breakdown — a label
/// and the (signed, negative) amount it took off, rendered as a
/// regular offset line row rather than a pill.
///
/// [amount] is signed minor units (negative; it reduces the
/// total). A plain display shape so the shared widget never
/// depends on a billing feature's own discount model.
class InvoiceDiscount extends Equatable {
  final String label;
  final int amount;

  const InvoiceDiscount({
    required this.label,
    required this.amount,
  });

  @override
  List<Object?> get props => [label, amount];
}

/// Normalised, presentation-only shape consumed by the
/// shared [InvoiceBreakdown] widget.
///
/// Callers (the member-detail billing dialogs) build one of
/// these from whichever backend shape they hold — a preview, a
/// historical payment, a finalized invoice, or a before/after
/// comparison — so the widget has a single render path for all.
/// Money is stored in minor units; formatting happens at render
/// via `formatMinorUnits`.
class InvoiceBreakdownData extends Equatable {
  final List<InvoiceLineItem> lines;

  /// Optional pre-discount subtotal. Rendered as a muted
  /// line above the divider when present.
  final int? subtotal;

  final List<InvoiceDiscount> appliedDiscounts;

  /// Every charge against the invoice (retries, success,
  /// refunds). Rendered as an "Attempts" section when present.
  final List<InvoiceAttemptLine> attempts;

  final int total;
  final String currency;

  /// When true the [total] row reads "Refunded" instead of
  /// [totalLabel] — refunds render the same breakdown, relabeled.
  final bool isRefund;

  /// Amount refunded against this charge (minor units, >= 0).
  /// When non-zero a "Refunded" line and a "Net" line render
  /// below the total, so it's clear what was returned.
  final int refundedAmount;

  /// Optional **prior total** for a before→after comparison. When
  /// set, the total row renders old → new and a "Difference" row
  /// appears below it.
  final int? previousTotal;

  /// Label for the total row, e.g. "Total" (default) or "Monthly"
  /// for a recurring/comparison view. [isRefund] still wins.
  final String totalLabel;

  /// Optional suffix appended to the total + difference amounts in a
  /// recurring view (e.g. "/mo"). Per-line rows carry no suffix.
  final String? amountSuffix;

  const InvoiceBreakdownData({
    required this.lines,
    required this.total,
    required this.currency,
    this.subtotal,
    this.appliedDiscounts = const [],
    this.attempts = const [],
    this.isRefund = false,
    this.refundedAmount = 0,
    this.previousTotal,
    this.totalLabel = 'Total',
    this.amountSuffix,
  });

  @override
  List<Object?> get props => [
        lines,
        subtotal,
        appliedDiscounts,
        attempts,
        total,
        currency,
        isRefund,
        refundedAmount,
        previousTotal,
        totalLabel,
        amountSuffix,
      ];
}
