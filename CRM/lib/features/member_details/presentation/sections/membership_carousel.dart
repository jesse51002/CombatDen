import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/sections/discounts_section.dart';
import 'package:crm/features/member_details/presentation/sections/membership_actions_row.dart';
import 'package:crm/features/member_details/presentation/sections/membership_details_table.dart';
import 'package:crm/features/member_details/presentation/sections/outdated_price_card.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/filter_pills.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Paged membership card — one membership at a time with
/// prev/next navigation. Each page is **atomic to a single
/// covered member**: a member selector (when the plan covers a
/// family) switches whose cost, usage, and discounts are shown,
/// defaulting to the queried member. The plan header, details
/// table, the outdated-price prompt, discounts, and the
/// account actions row make up a page.
class MembershipCarousel extends StatefulWidget {
  final MemberDetailResponse member;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  /// When true (wide grid, where the card is stretched to fill
  /// the right column), the actions row pins to the card's
  /// bottom edge and the slack collects above it. Must stay
  /// false in the stacked layout, where height is unbounded and
  /// a [Spacer] would have no constraints.
  final bool expand;

  const MembershipCarousel({
    super.key,
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
    this.expand = false,
  });

  @override
  State<MembershipCarousel> createState() =>
      _MembershipCarouselState();
}

class _MembershipCarouselState extends State<MembershipCarousel> {
  /// The covered member whose atomic view is shown. Null falls
  /// back to the default subject for the current plan.
  String? _selectedMemberId;

  List<MembershipInfo> get _memberships =>
      widget.member.memberships;

  @override
  void didUpdateWidget(covariant MembershipCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Paging to another plan resets the selector to its
    // default subject for the new plan.
    if (oldWidget.currentIndex != widget.currentIndex) {
      _selectedMemberId = null;
    }
  }

  /// The default covered subject for a membership: the queried
  /// member when they hold a slot, else the first covered
  /// person, else the queried member id.
  String _defaultSubject(MembershipInfo membership) {
    if (membership.members.containsKey(widget.member.memberId)) {
      return widget.member.memberId;
    }
    if (membership.members.isNotEmpty) {
      return membership.members.keys.first;
    }
    return widget.member.memberId;
  }

  /// Covered member ids in a stable order: the queried member
  /// first, then any others on the plan.
  List<String> _coveredIds(MembershipInfo membership) {
    final ids = membership.members.keys.toList();
    ids.sort((a, b) {
      if (a == widget.member.memberId) return -1;
      if (b == widget.member.memberId) return 1;
      return 0;
    });
    return ids;
  }

  /// The effective selected id — the local pick when still on
  /// the current plan, else the default subject.
  String _effectiveId(MembershipInfo membership) {
    final picked = _selectedMemberId;
    if (picked != null && membership.members.containsKey(picked)) {
      return picked;
    }
    return _defaultSubject(membership);
  }

  /// First name for a covered member, for the selector pill.
  String _firstNameFor(MembershipInfo membership, String id) {
    if (id == widget.member.memberId) {
      return widget.member.firstName;
    }
    return membership.payingForMemberFor(id)?.firstName ?? 'Member';
  }

  /// Full name for a covered member, for dialogs / prompts.
  String _fullNameFor(MembershipInfo membership, String id) {
    if (id == widget.member.memberId) {
      return widget.member.fullName;
    }
    return membership.payingForMemberFor(id)?.fullName ?? 'Member';
  }

  /// The covered member's own display status, falling back to
  /// the plan-level status when they are not in the roster.
  MembershipStatus _statusFor(
    MembershipInfo membership,
    String id,
  ) =>
      membership.payingForMemberFor(id)?.status ??
      membership.status;

  @override
  Widget build(BuildContext context) {
    if (_memberships.isEmpty) {
      return _EmptyMembershipCard();
    }

    final index =
        widget.currentIndex.clamp(0, _memberships.length - 1);
    final membership = _memberships[index];
    final hasMultiple = _memberships.length > 1;

    final coveredIds = _coveredIds(membership);
    final selectedId = _effectiveId(membership);
    final selectedStatus = _statusFor(membership, selectedId);

    // Show the member selector whenever the membership covers
    // someone other than just the viewed member — including a
    // single covered person who isn't them (a parent viewing a
    // child's membership), so the card never implies it's the
    // viewed member's own. Hide it only when the sole covered
    // person IS the viewed member.
    final showSelector = coveredIds.isNotEmpty &&
        !(coveredIds.length == 1 &&
            coveredIds.first == widget.member.memberId);
    final showOutdated = !isTerminalStatus(selectedStatus) &&
        membership.isOnOutdatedPriceFor(selectedId) &&
        membership.currentActivePrice != null;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          _CarouselHeader(
            membership: membership,
            currentIndex: index,
            total: _memberships.length,
            hasMultiple: hasMultiple,
            onPrevious: index > 0
                ? () => widget.onPageChanged(index - 1)
                : null,
            onNext: index < _memberships.length - 1
                ? () => widget.onPageChanged(index + 1)
                : null,
          ),
          if (showSelector)
            FilterPills(
              labels: [
                for (final id in coveredIds)
                  _firstNameFor(membership, id),
              ],
              selectedIndex: coveredIds.indexOf(selectedId),
              onSelected: (i) => setState(
                () => _selectedMemberId = coveredIds[i],
              ),
            ),
          MembershipDetailsTable(
            membership: membership,
            coveredMemberId: selectedId,
          ),
          if (showOutdated)
            OutdatedPriceCard(
              membership: membership,
              coveredMemberId: selectedId,
              coveredMemberName:
                  _fullNameFor(membership, selectedId),
            ),
          DiscountsSection(
            member: widget.member,
            membership: membership,
            coveredMemberId: selectedId,
          ),
          if (widget.expand) const Spacer(),
          MembershipActionsRow(
            member: widget.member,
            currentMembership: membership,
          ),
        ],
      ),
    );
  }
}

class _EmptyMembershipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('Membership', style: DesignConstants.h2),
          Container(
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
                'No memberships',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselHeader extends StatelessWidget {
  final MembershipInfo membership;
  final int currentIndex;
  final int total;
  final bool hasMultiple;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _CarouselHeader({
    required this.membership,
    required this.currentIndex,
    required this.total,
    required this.hasMultiple,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasMultiple)
          Semantics(
            label: 'Previous membership',
            child: IconButton(
              onPressed: onPrevious,
              tooltip: 'Previous membership',
              icon: Icon(
                Symbols.chevron_left_sharp,
                color: onPrevious != null
                    ? DesignConstants.text
                    : DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              Text(
                membership.displayName,
                style: DesignConstants.h1,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasMultiple)
                Semantics(
                  label:
                      'Membership ${currentIndex + 1} of '
                      '$total',
                  child: Text(
                    '${currentIndex + 1} / $total '
                    'memberships',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasMultiple)
          Semantics(
            label: 'Next membership',
            child: IconButton(
              onPressed: onNext,
              tooltip: 'Next membership',
              icon: Icon(
                Symbols.chevron_right_sharp,
                color: onNext != null
                    ? DesignConstants.text
                    : DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ),
      ],
    );
  }
}
