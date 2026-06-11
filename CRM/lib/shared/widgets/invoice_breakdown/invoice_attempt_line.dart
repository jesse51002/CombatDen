import 'package:equatable/equatable.dart';

import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

/// One payment attempt against an invoice — a retry, the
/// success, or a refund — as a presentation-only row.
///
/// A plain display shape so the shared widget never depends
/// on a billing feature's charge model; the member-detail
/// dialog adapts its richer model into this.
class InvoiceAttemptLine extends Equatable {
  /// How it was paid, e.g. "•••• 4242", "Cash", "Card".
  final String method;

  /// Formatted timestamp for the attempt.
  final String timeLabel;

  /// Signed amount in minor units (refunds are negative).
  final int amount;

  /// "Succeeded" / "Failed" / "Refunded" / …
  final String statusLabel;
  final InvoiceChipTone statusTone;

  const InvoiceAttemptLine({
    required this.method,
    required this.timeLabel,
    required this.amount,
    required this.statusLabel,
    required this.statusTone,
  });

  @override
  List<Object?> get props =>
      [method, timeLabel, amount, statusLabel, statusTone];
}
