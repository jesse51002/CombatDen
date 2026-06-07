import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';
import 'package:crm/features/member_details/data/models/upcoming_invoice_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/coming_soon_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Stripe invoice status that counts as outstanding/open.
const _kOpenStatus = 'open';

/// Bundle of the two read-only invoice reads this card uses.
class _InvoicesData {
  final List<PaymentsInvoiceResponse> invoices;
  final UpcomingInvoiceResponse? upcoming;

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

  const _PickedInvoice({
    required this.overdue,
    required this.amount,
    required this.currency,
    required this.date,
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

  const InvoicesSection({
    super.key,
    required this.memberId,
    required this.gymId,
    required this.payerName,
    this.nextDueDate,
    this.payerPhotoUrl,
  });

  @override
  State<InvoicesSection> createState() =>
      _InvoicesSectionState();
}

class _InvoicesSectionState extends State<InvoicesSection> {
  late final Future<_InvoicesData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
        // Own top gap so the parent column needs no `spacing` —
        // that way an absent invoice leaves no dead strip and the
        // membership card fills the whole column.
        return Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.spacingBig,
          ),
          child: _InvoiceCard(
            invoice: invoice,
            payerName: widget.payerName,
            payerPhotoUrl: widget.payerPhotoUrl,
          ),
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
              Text(
                formatMinorUnits(
                  invoice.amount,
                  currency: invoice.currency,
                ),
                style: DesignConstants.h2.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
