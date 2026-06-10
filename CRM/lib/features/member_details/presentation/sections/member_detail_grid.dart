import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/sections/invoices_section.dart';
import 'package:crm/features/member_details/presentation/sections/member_waivers_section.dart';
import 'package:crm/features/member_details/presentation/sections/membership_carousel.dart';
import 'package:crm/features/member_details/presentation/sections/payment_history_section.dart';
import 'package:crm/features/member_details/presentation/sections/personal_info_section.dart';
import 'package:crm/features/member_details/presentation/sections/rank_section.dart';
import 'package:crm/features/member_details/presentation/sections/retention_section.dart';

/// Responsive body of the member detail screen.
///
/// Desktop (≥ [AppConstants.breakpointTablet]): a two-column grid —
/// personal info, rank, and retention stacked on the left; the membership
/// carousel and the account's Invoices card stacked on the right (the
/// invoices sit with the membership they relate to). Below the breakpoint
/// everything stacks into a single column. Below the grid, the account-level
/// Payment History card spans full width (it is not tied to one membership).
class MemberDetailGrid extends StatelessWidget {
  final MemberDetailResponse member;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  /// Bumped by the bloc on every member mutation; threaded to the
  /// Invoices card so it re-fetches after a discount / membership change.
  final int refreshToken;

  const MemberDetailGrid({
    super.key,
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
    required this.refreshToken,
  });

  /// The account's soonest upcoming billing date across its
  /// memberships — labels the next invoice (which carries no
  /// date of its own).
  DateTime? get _nextDueDate {
    DateTime? soonest;
    for (final m in member.memberships) {
      final due = m.nextDueDate;
      if (due == null) continue;
      if (soonest == null || due.isBefore(soonest)) {
        soonest = due;
      }
    }
    return soonest;
  }

  /// The paying account behind the invoices — this member when
  /// unlinked, else the linked parent account.
  LinkedAccount? get _payer {
    final parentId = member.linkedToAccount;
    if (parentId == null) return null;
    for (final a in member.linkedAccounts) {
      if (a.memberId == parentId) return a;
    }
    return null;
  }

  String get _payerName => _payer?.fullName ?? member.fullName;

  String? get _payerPhotoUrl =>
      _payer?.photoUrl ?? member.photoUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        _Grid(
          member: member,
          currentIndex: currentIndex,
          onPageChanged: onPageChanged,
          nextDueDate: _nextDueDate,
          payerName: _payerName,
          payerPhotoUrl: _payerPhotoUrl,
          refreshToken: refreshToken,
        ),
        PaymentHistorySection(
          memberId: member.memberId,
          gymId: member.gymId,
        ),
      ],
    );
  }
}

/// The responsive two-column (or stacked) upper grid. The right column
/// stacks the membership carousel and the Invoices card.
class _Grid extends StatelessWidget {
  final MemberDetailResponse member;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final DateTime? nextDueDate;
  final String payerName;
  final String? payerPhotoUrl;
  final int refreshToken;

  const _Grid({
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
    required this.nextDueDate,
    required this.payerName,
    required this.payerPhotoUrl,
    required this.refreshToken,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >=
            AppConstants.breakpointTablet;
        final left = _LeftColumn(member: member, expand: wide);
        final carousel = MembershipCarousel(
          member: member,
          currentIndex: currentIndex,
          onPageChanged: onPageChanged,
          expand: wide,
        );
        final invoices = InvoicesSection(
          memberId: member.memberId,
          gymId: member.gymId,
          nextDueDate: nextDueDate,
          payerName: payerName,
          payerPhotoUrl: payerPhotoUrl,
          refreshKey: refreshToken,
        );
        // Right column: the membership card fills the column down
        // to the (usually taller) left column's height, with the
        // Invoices card (at most one invoice, may be absent) at
        // the bottom. No column `spacing` here: when there is no
        // invoice the Invoices section collapses to nothing and
        // the membership must fill the WHOLE column (a column gap
        // would leave a dead strip below it). The Invoices card
        // supplies its own top gap when it is actually present.
        final right = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) Expanded(child: carousel) else carousel,
            invoices,
          ],
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [left, right],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              Expanded(child: left),
              Expanded(child: right),
            ],
          ),
        );
      },
    );
  }
}

/// Left grid column: personal info, rank, and retention,
/// stacked. In the wide grid the retention card fills the column
/// (content stays at the top, slack at the bottom) so the two
/// columns bottom-align.
class _LeftColumn extends StatelessWidget {
  final MemberDetailResponse member;

  /// When true (wide grid), the retention card stretches to fill
  /// the column. Must stay false in the stacked layout, where
  /// height is unbounded and an [Expanded] would have no
  /// constraints.
  final bool expand;

  const _LeftColumn({required this.member, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final retention = RetentionSection(
      retention: member.retention,
      rewards: member.recentlyRedeemedRewards,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        PersonalInfoSection(
          personalInfo: member.personalInfo,
        ),
        MemberWaiversSection(
          memberId: member.memberId,
          gymId: member.gymId,
        ),
        if (member.rank != null)
          RankSection(rank: member.rank!),
        if (expand) Expanded(child: retention) else retention,
      ],
    );
  }
}
