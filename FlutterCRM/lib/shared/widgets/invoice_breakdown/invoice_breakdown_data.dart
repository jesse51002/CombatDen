import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/line_item_record.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';

/// Which backend shape this breakdown was built from.
enum InvoiceKind { preview, historical, finalized }

/// One row inside an [InvoiceBreakdownData].
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

/// Normalised shape consumed by the shared
/// `InvoiceBreakdown` widget. Callers build one of these
/// via the adapter factories and hand it to the widget —
/// which then has a single rendering path for previews,
/// historical payments and finalized invoices.
class InvoiceBreakdownData extends Equatable {
  final List<InvoiceLineItem> lines;
  final int? subtotal;
  final List<DiscountInfo> appliedDiscounts;
  final int total;
  final String currency;
  final InvoiceKind kind;

  final ChargeStatus? status;
  final DateTime? chargeTime;

  final String? hostedInvoiceUrl;
  final String? invoicePdfUrl;

  final String? chargeId;
  final bool isRefund;

  const InvoiceBreakdownData({
    required this.lines,
    required this.total,
    required this.currency,
    required this.kind,
    this.subtotal,
    this.appliedDiscounts = const [],
    this.status,
    this.chargeTime,
    this.hostedInvoiceUrl,
    this.invoicePdfUrl,
    this.chargeId,
    this.isRefund = false,
  });

  factory InvoiceBreakdownData.fromPreview(
    PaymentsInvoicePreviewResponse r,
  ) {
    return InvoiceBreakdownData(
      lines: r.lines
          .map(
            (l) => InvoiceLineItem(
              description: l.description ?? 'Line item',
              amount: l.amount,
            ),
          )
          .toList(),
      subtotal: r.subtotal,
      total: r.total,
      currency: r.currency,
      kind: InvoiceKind.preview,
    );
  }

  factory InvoiceBreakdownData.fromPayment(
    PaymentRecord r,
  ) {
    return InvoiceBreakdownData(
      lines: r.lineItems
          .map(
            (LineItemRecord l) => InvoiceLineItem(
              description: l.name,
              amount: l.amount,
            ),
          )
          .toList(),
      appliedDiscounts: r.appliedDiscounts,
      total: r.amount,
      currency: r.currency,
      kind: InvoiceKind.historical,
      status: r.status,
      chargeTime: r.chargeTime,
      chargeId: r.chargeId,
      isRefund: r.kind == ChargeKind.refund,
    );
  }

  factory InvoiceBreakdownData.fromInvoice(
    PaymentsInvoiceResponse r, {
    List<LineItemRecord>? lines,
  }) {
    return InvoiceBreakdownData(
      lines: (lines ?? const <LineItemRecord>[])
          .map(
            (l) => InvoiceLineItem(
              description: l.name,
              amount: l.amount,
            ),
          )
          .toList(),
      total: r.amountDue,
      currency: r.currency,
      kind: InvoiceKind.finalized,
      chargeTime: r.createdAt,
      hostedInvoiceUrl: r.hostedInvoiceUrl,
      invoicePdfUrl: r.invoicePdf,
    );
  }

  @override
  List<Object?> get props => [
        lines,
        subtotal,
        appliedDiscounts,
        total,
        currency,
        kind,
        status,
        chargeTime,
        hostedInvoiceUrl,
        invoicePdfUrl,
        chargeId,
        isRefund,
      ];
}
