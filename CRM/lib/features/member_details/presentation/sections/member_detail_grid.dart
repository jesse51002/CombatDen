import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/sections/invoices_section.dart';
import 'package:crm/features/member_details/presentation/sections/member_waivers_section.dart';
import 'package:crm/features/member_details/presentation/sections/membership_carousel.dart';
import 'package:crm/features/member_details/presentation/sections/payment_history_section.dart';
import 'package:crm/features/member_details/presentation/sections/personal_info_section.dart';
import 'package:crm/features/member_details/presentation/sections/rank_section.dart';
import 'package:crm/features/member_details/presentation/sections/retention_section.dart';
import 'package:crm/shared/widgets/balanced_columns.dart';

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

  /// Bumped by the bloc on every member mutation (and on each tick of
  /// the post-charge invoice poll); threaded to the Invoices card and
  /// the Payment history card so both re-fetch after a discount /
  /// membership / charge change.
  final int refreshToken;

  const MemberDetailGrid({
    super.key,
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
    required this.refreshToken,
  });

  /// The distinct payers behind this member's recurring memberships
  /// (self and/or their linked parent), each with the soonest next-due
  /// date among the memberships they fund. One Invoices card is shown
  /// per payer — up to two when the memberships are split. Membership
  /// order is preserved so the dominant payer leads.
  List<InvoicePayer> get _invoicePayers {
    final order = <String>[];
    final dueByPayer = <String, DateTime?>{};

    // For each payer, capture ONE representative funded (itemId, coveredMemberId)
    // so the cash mark-paid action has a handle to the open invoice.
    final cashItemIdByPayer = <String, String>{};
    final cashMemberIdByPayer = <String, String>{};

    for (final m in member.memberships) {
      if (m.planType?.toLowerCase() != 'recurring') continue;
      final payerId = m.paidByMemberId;
      final due = m.nextDueDate;
      if (!dueByPayer.containsKey(payerId)) {
        order.add(payerId);
        dueByPayer[payerId] = due;
      } else {
        final current = dueByPayer[payerId];
        if (due != null &&
            (current == null || due.isBefore(current))) {
          dueByPayer[payerId] = due;
        }
      }
      // Capture the first funded membership we find for this payer.
      // Each card is the viewed member's own membership, so the cash
      // handle is its item id + the viewed member.
      if (!cashItemIdByPayer.containsKey(payerId)) {
        cashItemIdByPayer[payerId] = m.itemId;
        cashMemberIdByPayer[payerId] = member.memberId;
      }
    }
    return [
      for (final id in order)
        InvoicePayer(
          memberId: id,
          name: _payerNameFor(id),
          photoUrl: _payerPhotoFor(id),
          nextDueDate: dueByPayer[id],
          cashItemId: cashItemIdByPayer[id],
          cashMemberId: cashMemberIdByPayer[id],
        ),
    ];
  }

  String _payerNameFor(String id) {
    if (id == member.memberId) return member.fullName;
    for (final a in member.authorizedPayers) {
      if (a.memberId == id) return a.fullName;
    }
    return 'Authorized payer';
  }

  String? _payerPhotoFor(String id) {
    if (id == member.memberId) return member.photoUrl;
    for (final a in member.authorizedPayers) {
      if (a.memberId == id) return a.photoUrl;
    }
    return null;
  }

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
          payers: _invoicePayers,
          refreshToken: refreshToken,
        ),
        PaymentHistorySection(
          memberId: member.memberId,
          gymId: member.gymId,
          refreshKey: refreshToken,
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
  final List<InvoicePayer> payers;
  final int refreshToken;

  const _Grid({
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
    required this.payers,
    required this.refreshToken,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >=
            AppConstants.breakpointTablet;
        final leftChildren = <Widget>[
          PersonalInfoSection(
            personalInfo: member.personalInfo,
          ),
          MemberWaiversSection(
            memberId: member.memberId,
            gymId: member.gymId,
          ),
          if (member.rank != null)
            RankSection(rank: member.rank!),
          RetentionSection(
            retention: member.retention,
            rewards: member.recentlyRedeemedRewards,
          ),
        ];
        final carousel = MembershipCarousel(
          member: member,
          currentIndex: currentIndex,
          onPageChanged: onPageChanged,
        );
        final invoices = InvoicesSection(
          gymId: member.gymId,
          payers: payers,
          refreshKey: refreshToken,
          // In the wide grid BalancedColumns inserts the row
          // gap only when the card actually renders.
          topGap: !wide,
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              ...leftChildren,
              // No gap slot between the carousel and the
              // Invoices card: when there is no invoice the
              // Invoices section collapses to nothing (a
              // column gap would leave a dead strip); it
              // supplies its own top gap when present.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [carousel, invoices],
              ),
            ],
          );
        }
        // Wide: BalancedColumns lays every card at its natural
        // size, then hands the height deficit of the shorter
        // column to its filler card — the retention card on the
        // left, the membership carousel on the right (so the
        // Invoices card stays pinned at the bottom).
        return BalancedColumns(
          left: leftChildren,
          right: [carousel, invoices],
          fillerIndexLeft: leftChildren.length - 1,
          fillerIndexRight: 0,
          columnSpacing: DesignConstants.spacingBig,
          rowSpacing: DesignConstants.spacingBig,
        );
      },
    );
  }
}
