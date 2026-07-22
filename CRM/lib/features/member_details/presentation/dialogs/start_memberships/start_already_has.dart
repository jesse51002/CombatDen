import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plan_rules.dart'
    as rules;
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

/// Compact "Already has" block at the top of a member's
/// Plans step: the non-terminal memberships the member
/// already holds (plan name + status chip), built from the
/// same best-effort detail fetch that powers the
/// already-on-this-plan rule. The caller hides the block
/// when there are none (or when the fetch failed).
class StartAlreadyHas extends StatelessWidget {
  final String memberId;

  /// Non-terminal memberships covering [memberId], per
  /// `rules.currentMembershipsForParticipant`.
  final List<MembershipInfo> memberships;

  const StartAlreadyHas({
    super.key,
    required this.memberId,
    required this.memberships,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(
            'Already has',
            style: DesignConstants.pSmallBold.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          for (final m in memberships)
            _AlreadyHasRow(
              planName: m.planName,
              status: rules.participantStatus(m, memberId),
            ),
        ],
      ),
    );
  }
}

class _AlreadyHasRow extends StatelessWidget {
  final String planName;
  final MembershipStatus status;

  const _AlreadyHasRow({
    required this.planName,
    required this.status,
  });

  InvoiceChipTone get _tone {
    switch (status) {
      case MembershipStatus.active:
      case MembershipStatus.trial:
        return InvoiceChipTone.good;
      case MembershipStatus.frozen:
      // Dormant is still a LIVE pack, just an unused one — the member does
      // already have this membership, which is what this dialog warns about.
      case MembershipStatus.dormant:
        return InvoiceChipTone.warning;
      case MembershipStatus.overdue:
        return InvoiceChipTone.bad;
      case MembershipStatus.cancelled:
      case MembershipStatus.ended:
      case MembershipStatus.noMembership:
      case MembershipStatus.unknown:
        return InvoiceChipTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            planName,
            style: DesignConstants.p,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InvoiceChip(
          label: status.displayLabel,
          tone: _tone,
        ),
      ],
    );
  }
}
