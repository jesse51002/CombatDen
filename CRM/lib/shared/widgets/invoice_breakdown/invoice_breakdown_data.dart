import 'package:equatable/equatable.dart';

/// One line on an invoice breakdown: a label and a signed
/// amount in minor currency units (cents for USD).
class InvoiceLineItem extends Equatable {
  final String description;
  final int amount;

  const InvoiceLineItem({
    required this.description,
    required this.amount,
  });

  @override
  List<Object?> get props => [description, amount];
}

/// One applied-discount pill on an invoice breakdown.
///
/// A plain display shape (label + optional sub-label) so
/// the shared widget never depends on a billing feature's
/// own discount model — the member-detail dialogs adapt
/// their richer models into this when composing the
/// breakdown.
class InvoiceDiscount extends Equatable {
  final String label;
  final String? subLabel;

  const InvoiceDiscount({
    required this.label,
    this.subLabel,
  });

  @override
  List<Object?> get props => [label, subLabel];
}

/// Normalised, presentation-only shape consumed by the
/// shared [InvoiceBreakdown] widget.
///
/// Callers (the member-detail billing dialogs in a later
/// workflow) build one of these from whichever backend
/// shape they hold — a preview, a historical payment, or a
/// finalized invoice — so the widget has a single render
/// path for all three. Money is stored in minor units;
/// formatting happens at render via `formatMinorUnits`.
class InvoiceBreakdownData extends Equatable {
  final List<InvoiceLineItem> lines;

  /// Optional pre-discount subtotal. Rendered as a muted
  /// line above the divider when present.
  final int? subtotal;

  final List<InvoiceDiscount> appliedDiscounts;

  final int total;
  final String currency;

  /// When true the [total] row reads "Refunded" instead of
  /// "Total" — refunds render the same breakdown, relabeled.
  final bool isRefund;

  /// Amount refunded against this charge (minor units, >= 0).
  /// When non-zero a "Refunded" line and a "Net" line render
  /// below the total, so it's clear what was returned.
  final int refundedAmount;

  const InvoiceBreakdownData({
    required this.lines,
    required this.total,
    required this.currency,
    this.subtotal,
    this.appliedDiscounts = const [],
    this.isRefund = false,
    this.refundedAmount = 0,
  });

  @override
  List<Object?> get props => [
        lines,
        subtotal,
        appliedDiscounts,
        total,
        currency,
        isRefund,
        refundedAmount,
      ];
}
