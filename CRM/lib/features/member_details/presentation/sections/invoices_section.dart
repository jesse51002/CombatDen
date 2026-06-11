import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/coming_soon_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Stripe invoice status that counts as outstanding/open.
const _kOpenStatus = 'open';

/// Bundle of the two read-only invoice reads this card uses.
class _InvoicesData {
  final List<PaymentsInvoiceResponse> invoices;
  final PreviewInvoice? upcoming;

  const _InvoicesData({
    required this.invoices,
    required this.upcoming,
  });
}

/// The single invoice the card surfaces.
class _PickedInvoice {
  final bool overdue;
  final int amount;
  final String currency;
  final DateTime? date;

  /// The upcoming preview (carries line items) when this is the
  /// upcoming invoice; null for an open/overdue invoice, which the
  /// list endpoint surfaces as an amount only.
  final PreviewInvoice? preview;

  const _PickedInvoice({
    required this.overdue,
    required this.amount,
    required this.currency,
    required this.date,
    this.preview,
  });
}

/// Account-level Invoices card (sits with the membership in the
/// right column). Shows **one** invoice at a time — the overdue
/// one if there is any, otherwise the next (upcoming) one — with
/// the payer, amount, due date, and an in-card mark-paid-with-cash
/// action. When the account has neither, the card renders nothing.
/// Read-only side reads (its own [FutureBuilder], like Waivers).
class InvoicesSection extends StatefulWidget {
  final String memberId;
  final String gymId;

  /// The account's next billing date, used to label the upcoming
  /// invoice (the upcoming-invoice preview carries no date).
  final DateTime? nextDueDate;

  /// The paying account this invoice belongs to.
  final String payerName;
  final String? payerPhotoUrl;

  /// Re-fetches the invoices whenever this changes — bump it after a
  /// billing mutation (discount or membership add/remove) so the card
  /// reflects the new charge instead of the one loaded at first build.
  final Object? refreshKey;

  /// Whether the card supplies its own top gap when it has an
  /// invoice to show. The stacked layout keeps this on (its
  /// parent column has no gap slot, so an absent invoice leaves
  /// no dead strip); the wide grid turns it off because
  /// `BalancedColumns` adds the row gap only when the card
  /// actually renders.
  final bool topGap;

  const InvoicesSection({
    super.key,
    required this.memberId,
    required this.gymId,
    required this.payerName,
    this.nextDueDate,
    this.payerPhotoUrl,
    this.refreshKey,
    this.topGap = true,
  });

  @override
  State<InvoicesSection> createState() =>
      _InvoicesSectionState();
}

class _InvoicesSectionState extends State<InvoicesSection> {
  late Future<_InvoicesData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant InvoicesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<_InvoicesData> _load() async {
    final repo = MemberRepository(apiClient: ApiClient());
    final invoicesF = repo.listMemberInvoices(widget.memberId);
    final upcomingF = repo.getUpcomingInvoice(widget.memberId);
    return _InvoicesData(
      invoices: await invoicesF,
      upcoming: await upcomingF,
    );
  }

  /// Pick the one invoice to show: an overdue (open) one first,
  /// otherwise the upcoming one, otherwise none.
  _PickedInvoice? _pick(_InvoicesData data) {
    final open = data.invoices
        .where((i) => i.status == _kOpenStatus)
        .toList();
    if (open.isNotEmpty) {
      final i = open.first;
      return _PickedInvoice(
        overdue: true,
        amount: i.amountRemaining,
        currency: i.currency,
        date: i.createdAt,
      );
    }
    final upcoming = data.upcoming;
    if (upcoming != null) {
      return _PickedInvoice(
        overdue: false,
        amount: upcoming.amountDue,
        currency: upcoming.currency,
        date: widget.nextDueDate,
        preview: upcoming,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InvoicesData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final invoice = _pick(data);
        if (invoice == null) return const SizedBox.shrink();
        final card = _InvoiceCard(
          invoice: invoice,
          payerName: widget.payerName,
          payerPhotoUrl: widget.payerPhotoUrl,
        );
        if (!widget.topGap) return card;
        // Own top gap so the parent column needs no `spacing` —
        // that way an absent invoice leaves no dead strip and the
        // membership card fills the whole column.
        return Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.spacingBig,
          ),
          child: card,
        );
      },
    );
  }
}

/// The Invoices card body — the single invoice rendered directly
/// in the card (no nested tile): eyebrow, payer, due date,
/// amount, and the cash action.
class _InvoiceCard extends StatelessWidget {
  final _PickedInvoice invoice;
  final String payerName;
  final String? payerPhotoUrl;

  const _InvoiceCard({
    required this.invoice,
    required this.payerName,
    required this.payerPhotoUrl,
  });

  /// The money this card shows, through the shared breakdown widget.
  /// An upcoming invoice carries line items; an open/overdue one is
  /// surfaced as an amount-only total.
  InvoiceBreakdownData get _money {
    final preview = invoice.preview;
    if (preview != null) return previewInvoiceBreakdown(preview);
    return InvoiceBreakdownData(
      lines: const [],
      total: invoice.amount,
      currency: invoice.currency,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Invoice', style: DesignConstants.h2),
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              CircleAvatar(
                radius: DesignConstants.iconSizeMedium,
                backgroundColor: DesignConstants.backgroundColor,
                backgroundImage: payerPhotoUrl != null
                    ? NetworkImage(payerPhotoUrl!)
                    : null,
                child: payerPhotoUrl == null
                    ? Text(
                        payerName.isNotEmpty
                            ? payerName[0].toUpperCase()
                            : '?',
                        style: DesignConstants.pSmall.copyWith(
                          color: DesignConstants.text,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingTiny,
                  children: [
                    Text(
                      invoice.overdue ? 'Overdue' : 'Upcoming',
                      style: DesignConstants.pBig.copyWith(
                        color: invoice.overdue
                            ? DesignConstants.badRed
                            : DesignConstants.text2nd,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      payerName,
                      style: DesignConstants.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Due ${formatDay(invoice.date)}',
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          InvoiceBreakdown(data: _money),
          AppOutlineButton(
            fullWidth: true,
            text: 'Mark paid with cash',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: () => ComingSoonDialog.show(
              context: context,
              title: 'Mark paid with cash',
              message:
                  'Marking an invoice paid with cash is '
                  'coming soon.',
            ),
          ),
        ],
      ),
    );
  }
}
