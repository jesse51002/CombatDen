import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/mark_paid_cash_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_attribution.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Stripe invoice status that counts as outstanding/open.
const _kOpenStatus = 'open';

/// A payer whose invoice this card surfaces — the member themselves
/// (self-pay) or their linked parent. Under per-payer billing a member's
/// memberships can be split across two subscriptions, so one card is
/// rendered per distinct payer (up to two).
class InvoicePayer {
  final String memberId;
  final String name;
  final String? photoUrl;

  /// The payer's soonest next-due date among the memberships of this
  /// member they fund (the upcoming-invoice preview carries no date).
  final DateTime? nextDueDate;

  /// The `item_id` of a representative membership funded by this payer,
  /// used as the handle for marking an open invoice paid in cash.
  /// Null when the payer funds no resolvable recurring membership.
  final String? cashItemId;

  /// The covered member id whose membership [cashItemId] belongs to.
  /// Null when [cashItemId] is null.
  final String? cashMemberId;

  const InvoicePayer({
    required this.memberId,
    required this.name,
    this.photoUrl,
    this.nextDueDate,
    this.cashItemId,
    this.cashMemberId,
  });
}

/// A payer paired with the one invoice picked for them (or none).
class _PayerInvoice {
  final InvoicePayer payer;
  final _PickedInvoice? picked;

  const _PayerInvoice({required this.payer, this.picked});
}

/// The single invoice a payer's card surfaces.
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

/// Account-level Invoices card (sits with the membership in the right
/// column). Shows **one card per payer** of the member's memberships —
/// up to two when their memberships are split between self-pay and a
/// linked payer. Each card surfaces that payer's overdue invoice if any,
/// otherwise their next (upcoming) one, with the payer, amount, due date,
/// and an in-card mark-paid-with-cash action. When no payer has an
/// invoice, the section renders nothing. Read-only side reads (its own
/// [FutureBuilder], like Waivers).
class InvoicesSection extends StatefulWidget {
  final String gymId;

  /// The distinct payers behind this member's memberships (self and/or a
  /// linked parent). One invoice card is rendered per payer that has one.
  final List<InvoicePayer> payers;

  /// Re-fetches the invoices whenever this changes — bump it after a
  /// billing mutation (discount or membership add/remove) so the card
  /// reflects the new charge instead of the one loaded at first build.
  final Object? refreshKey;

  /// Whether the section supplies its own top gap when it has a card to
  /// show. The stacked layout keeps this on (its parent column has no gap
  /// slot, so an absent card leaves no dead strip); the wide grid turns it
  /// off because `BalancedColumns` adds the row gap only when the section
  /// actually renders.
  final bool topGap;

  const InvoicesSection({
    super.key,
    required this.gymId,
    required this.payers,
    this.refreshKey,
    this.topGap = true,
  });

  @override
  State<InvoicesSection> createState() =>
      _InvoicesSectionState();
}

class _InvoicesSectionState extends State<InvoicesSection> {
  late Future<List<_PayerInvoice>> _future;

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

  Future<List<_PayerInvoice>> _load() async {
    final repo = MemberRepository(apiClient: ApiClient());
    // Each payer's invoices come from THEIR own Stripe customer +
    // subscription, so the fetch is keyed on the payer, not the member.
    return Future.wait(
      widget.payers.map((p) async {
        final invoices = await repo.listMemberInvoices(p.memberId);
        final upcoming = await repo.getUpcomingInvoice(p.memberId);
        return _PayerInvoice(
          payer: p,
          picked: _pick(invoices, upcoming, p.nextDueDate),
        );
      }),
    );
  }

  /// Pick the one invoice to show for a payer: an overdue (open) one
  /// first, otherwise the upcoming one, otherwise none.
  _PickedInvoice? _pick(
    List<PaymentsInvoiceResponse> invoices,
    PreviewInvoice? upcoming,
    DateTime? nextDueDate,
  ) {
    final open = invoices
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
    if (upcoming != null) {
      return _PickedInvoice(
        overdue: false,
        amount: upcoming.amountDue,
        currency: upcoming.currency,
        date: nextDueDate,
        preview: upcoming,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_PayerInvoice>>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final bodies = [
          for (final pi in data)
            if (pi.picked != null)
              _InvoiceBody(
                invoice: pi.picked!,
                payer: pi.payer,
              ),
        ];
        if (bodies.isEmpty) return const SizedBox.shrink();
        // One card holds every payer's invoice, separated by spacing —
        // each block leads with its own payer header so the two read
        // as distinct invoices without needing separate cards.
        final content = SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              Text(
                bodies.length == 1 ? 'Invoice' : 'Invoices',
                style: DesignConstants.h2,
              ),
              ...bodies,
            ],
          ),
        );
        if (!widget.topGap) return content;
        // Own top gap so the parent column needs no `spacing` —
        // that way an absent card leaves no dead strip and the
        // membership card fills the whole column.
        return Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.spacingBig,
          ),
          child: content,
        );
      },
    );
  }
}

/// One payer's invoice block inside the shared Invoices card: the
/// payer header (eyebrow, name, due date), the amount breakdown, and
/// the cash action. The enclosing [InvoicesSection] owns the card and
/// stacks one of these per payer.
class _InvoiceBody extends StatelessWidget {
  final _PickedInvoice invoice;
  final InvoicePayer payer;

  const _InvoiceBody({
    required this.invoice,
    required this.payer,
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

  Widget? _cashAction(BuildContext context) {
    if (invoice.overdue && payer.cashItemId != null) {
      return AppOutlineButton(
        fullWidth: true,
        text: 'Mark paid with cash',
        borderRadius: DesignConstants.radiusSmall,
        onPressed: () => MarkPaidCashDialog.show(
          context: context,
          amount: invoice.amount,
          currency: invoice.currency,
          itemId: payer.cashItemId!,
          coveredMemberId: payer.cashMemberId!,
          payerName: payer.name,
        ),
      );
    }
    if (!invoice.overdue) {
      final dateNote = invoice.date != null
          ? 'Cash payment available once this invoice opens on '
            '${formatDay(invoice.date)}'
          : 'Cash payment available once this invoice opens';
      return Text(
        dateNote,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    // overdue but payer.cashItemId == null — no action.
    return null;
  }

  /// The status eyebrow line — "Overdue" (red) or "Upcoming", plus the due
  /// date. Sits above the shared breakdown; the payer identity (avatar +
  /// name) is the breakdown's attribution header.
  Widget _statusEyebrow() {
    final due = invoice.date;
    final dueText = due == null ? '' : ' · Due ${formatDay(due)}';
    return Text(
      '${invoice.overdue ? 'Overdue' : 'Upcoming'}$dueText',
      style: DesignConstants.pBig.copyWith(
        color: invoice.overdue
            ? DesignConstants.badRed
            : DesignConstants.text2nd,
        fontWeight: FontWeight.w700,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = _cashAction(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        _statusEyebrow(),
        InvoiceBreakdown(
          data: _money,
          // Whose invoice this is — the payer of this member's
          // memberships (self or a linked parent).
          attribution: InvoiceAttribution(
            name: payer.name,
            photoUrl: payer.photoUrl,
            caption: 'Billed to',
          ),
        ),
        ?action,
      ],
    );
  }
}
