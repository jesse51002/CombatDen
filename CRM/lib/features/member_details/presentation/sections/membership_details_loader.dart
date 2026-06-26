import 'package:flutter/material.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/sections/membership_details_table.dart';

/// Wraps [MembershipDetailsTable] with a side read of how much of a
/// ONE-TIME / TRIAL membership's charge has been refunded, so the table
/// shows a "Refunded" row under Cost once any of it is refunded. A
/// recurring membership skips the read entirely (its refunds live in
/// Payment History). The read is repository-direct — a documented
/// member-detail side read, like Invoices / Payment History — and
/// re-runs whenever [refreshKey] changes (bumped on every billing
/// mutation) or the carousel pages to a different membership.
class MembershipDetailsLoader extends StatefulWidget {
  final MembershipInfo membership;
  final String memberId;
  final String? payerName;
  final String? payerPhotoUrl;

  /// Re-fetches the refunded total whenever this changes — the member
  /// detail bloc's `refreshToken`.
  final Object? refreshKey;

  const MembershipDetailsLoader({
    super.key,
    required this.membership,
    required this.memberId,
    this.payerName,
    this.payerPhotoUrl,
    this.refreshKey,
  });

  @override
  State<MembershipDetailsLoader> createState() =>
      _MembershipDetailsLoaderState();
}

class _MembershipDetailsLoaderState
    extends State<MembershipDetailsLoader> {
  Future<int>? _refunded;

  bool get _isOneTimeOrTrial =>
      widget.membership.planType == PlanType.oneTime.value ||
      widget.membership.planType == PlanType.trial.value;

  @override
  void initState() {
    super.initState();
    if (_isOneTimeOrTrial) _refunded = _loadRefunded();
  }

  @override
  void didUpdateWidget(covariant MembershipDetailsLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-read when the page flips to a different membership or a billing
    // mutation (a refund, in particular) bumps the refresh key.
    if (oldWidget.membership.itemId != widget.membership.itemId ||
        oldWidget.refreshKey != widget.refreshKey) {
      setState(() {
        _refunded = _isOneTimeOrTrial ? _loadRefunded() : null;
      });
    }
  }

  /// Sum the refunded amount across this membership's charge(s) — the
  /// payment-history rows whose line items carry this membership's
  /// `item_id` (the same match the one-time refund flow uses to find a
  /// refundable charge).
  Future<int> _loadRefunded() async {
    final repo = MemberRepository(apiClient: ApiClient());
    final itemId = widget.membership.itemId;
    final payments =
        await repo.getPayments(widget.memberId, limit: 100, offset: 0);
    var total = 0;
    for (final p in payments) {
      if (p.kind == ChargeKind.payment &&
          p.lineItems.any((l) => l.itemId == itemId)) {
        total += p.refundedAmount;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final future = _refunded;
    if (future == null) {
      return MembershipDetailsTable(
        membership: widget.membership,
        payerName: widget.payerName,
        payerPhotoUrl: widget.payerPhotoUrl,
      );
    }
    // The table renders immediately (refunded row absent) and the row
    // appears once the read resolves — never a spinner over the table.
    return FutureBuilder<int>(
      future: future,
      builder: (context, snapshot) {
        return MembershipDetailsTable(
          membership: widget.membership,
          payerName: widget.payerName,
          payerPhotoUrl: widget.payerPhotoUrl,
          refundedAmount: snapshot.data,
        );
      },
    );
  }
}
