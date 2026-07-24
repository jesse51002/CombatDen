import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';

/// Stripe invoice status that counts as outstanding/open.
const kOpenInvoiceStatus = 'open';

/// The single invoice a payer's card surfaces.
class PickedInvoice {
  final bool overdue;
  final int amount;
  final String currency;
  final DateTime? date;

  /// The upcoming preview (carries line items) when this is the
  /// upcoming invoice; null for an open/overdue invoice, which the
  /// list endpoint surfaces as an amount only.
  final PreviewInvoice? preview;

  /// How many OPEN invoices this payer's subscription has. Normally 1;
  /// >1 is a stacked backlog, and a settle pays only [amount] (the newest)
  /// — the rest stay unpaid, so the card says so rather than implying the
  /// balance is cleared.
  final int openCount;

  /// Total still owed across ALL open subscription invoices — equals
  /// [amount] unless there is a backlog.
  final int openTotal;

  const PickedInvoice({
    required this.overdue,
    required this.amount,
    required this.currency,
    required this.date,
    this.preview,
    this.openCount = 1,
    this.openTotal = 0,
  });

  /// A settle would leave money behind.
  bool get hasBacklog => openCount > 1;
}

/// Pick the one invoice a payer's card surfaces: an overdue (open) one
/// first, otherwise the upcoming one, otherwise none.
///
/// **Only SUBSCRIPTION invoices are considered.** The card's actions
/// (Retry payment / Mark paid with cash) settle the payer's SUBSCRIPTION
/// invoice, which the backend resolves independently as the newest open
/// invoice on that subscription. Picking from the customer-wide list —
/// which also carries one-off / ad-hoc invoices — would let the card
/// confirm one figure while the backend charged another. Sorting
/// explicitly rather than trusting the list's order keeps "the newest"
/// the same invoice on both sides.
PickedInvoice? pickPayerInvoice(
  List<PaymentsInvoiceResponse> invoices,
  PreviewInvoice? upcoming,
  DateTime? nextDueDate,
) {
  final open = invoices
      .where((i) => i.status == kOpenInvoiceStatus)
      .where((i) => i.stripeSubscriptionId != null)
      .toList()
    ..sort((a, b) => b.created.compareTo(a.created));
  if (open.isNotEmpty) {
    final i = open.first;
    return PickedInvoice(
      overdue: true,
      amount: i.amountRemaining,
      currency: i.currency,
      date: i.createdAt,
      openCount: open.length,
      openTotal: open.fold(0, (sum, inv) => sum + inv.amountRemaining),
    );
  }
  if (upcoming != null) {
    return PickedInvoice(
      overdue: false,
      amount: upcoming.amountDue,
      currency: upcoming.currency,
      date: nextDueDate,
      preview: upcoming,
    );
  }
  return null;
}
