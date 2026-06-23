import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/payment_invoice_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/section_card.dart';

const int _kPageSize = 20;

/// Account-level payment history in its own full-width card.
/// Fetched on demand and paginated (a separate request from the
/// member detail) — read-only side read with its own state, like
/// the Waivers / Invoices sections. Returns the invoices this member
/// PAID, the invoices a membership they have ever held was on, and
/// the invoices that were FOR them (the payer's `paid_for`) — so a
/// charge a parent made for this member shows here. The "Paid by"
/// column names the payer; the invoice popup adds who it was "For".
/// Each row opens the full invoice (via [PaymentInvoiceDialog]);
/// "Show more" loads the next page. Reloads from page 1 whenever
/// [refreshKey] changes — bumped on every billing change (and on each
/// tick of the post-charge invoice poll) so a webhook-delivered
/// invoice surfaces here without a manual reload.
class PaymentHistorySection extends StatefulWidget {
  final String memberId;
  final String gymId;

  /// Bumped by the bloc on every billing change (the member-detail
  /// `refreshToken`). A change reloads the table from page 1.
  final int refreshKey;

  const PaymentHistorySection({
    super.key,
    required this.memberId,
    required this.gymId,
    required this.refreshKey,
  });

  @override
  State<PaymentHistorySection> createState() =>
      _PaymentHistorySectionState();
}

class _PaymentHistorySectionState
    extends State<PaymentHistorySection> {
  late final MemberRepository _repo;
  final List<PaymentRecord> _payments = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;

  /// Bumped on every [_reload] so an in-flight page fetch from a
  /// superseded load discards its result instead of appending stale
  /// rows onto the freshly-reset list.
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _repo = MemberRepository(apiClient: ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant PaymentHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      _reload();
    }
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    final gen = _loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.getPayments(
        widget.memberId,
        limit: _kPageSize,
        offset: _offset,
      );
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _payments.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _kPageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Resets pagination and re-fetches page 1. Bumping [_loadGen]
  /// orphans any in-flight [_load] so it can't append onto the
  /// cleared list.
  void _reload() {
    setState(() {
      _loadGen++;
      _payments.clear();
      _offset = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Payment history', style: DesignConstants.h2),
          _content(context),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_payments.isEmpty) {
      if (_loading) {
        return const Center(child: AppSpinner());
      }
      if (_error != null) {
        return ErrorMessage(message: _error!);
      }
      return _Empty();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        AppDataTable(
          shrinkWrap: true,
          showBackground: true,
          columns: const [
            AppDataTableColumn(label: 'Name', fill: true),
            AppDataTableColumn(label: 'Paid by', minWidth: 130),
            AppDataTableColumn(label: 'Date', minWidth: 110),
            AppDataTableColumn(label: '', minWidth: 92),
          ],
          rows: _payments
              .map((p) => _row(context, p))
              .toList(),
        ),
        if (_loading)
          const Center(child: AppSpinner())
        else if (_hasMore)
          AppOutlineButton(
            fullWidth: true,
            text: 'Show more',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: _load,
          ),
      ],
    );
  }

  AppDataTableRow _row(
    BuildContext context,
    PaymentRecord payment,
  ) {
    return AppDataTableRow(
      cells: [
        Text(
          _label(payment),
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          payment.paidByName.isNotEmpty
              ? payment.paidByName
              : '—',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          formatDay(payment.chargeTime),
          style: DesignConstants.h3,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: AppOutlineButton(
            text: 'Invoice',
            borderRadius: DesignConstants.radiusSmall,
            textStyle: DesignConstants.pSmall,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingSmall,
              vertical: DesignConstants.spacingTiny,
            ),
            onPressed: () => PaymentInvoiceDialog.show(
              context: context,
              payment: payment,
            ),
          ),
        ),
      ],
    );
  }

  /// "Monthly Pro · $50", with a refund suffix when part or
  /// all of the charge was returned.
  String _label(PaymentRecord payment) {
    final name = payment.lineItems.isNotEmpty
        ? payment.lineItems.first.name
        : payment.kind.displayLabel;
    final amount = formatMinorUnits(
      payment.amount,
      currency: payment.currency,
    );
    final base = '$name · $amount';
    if (payment.isFullyRefunded) {
      return '$base · Refunded';
    }
    if (payment.isPartiallyRefunded) {
      return '$base · Partially refunded';
    }
    return base;
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        DesignConstants.paddingBig,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Center(
        child: Text(
          'No payments yet',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
