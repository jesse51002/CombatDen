import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// ALREADY HAS — what this person is holding before anything is picked.
///
/// An eyebrow-and-pills group on the ground rather than a second card: it is
/// context for the grid below it, not a form of its own. Each pill is toned by
/// what its status MEANS, so a frozen membership and an active one are told
/// apart at a glance instead of by reading.
class PlansAlreadyHas extends StatelessWidget {
  final List<MembershipInfo> memberships;

  const PlansAlreadyHas({super.key, required this.memberships});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(WizardPlansCopy.alreadyHasEyebrow, style: scale.eyebrow),
        Wrap(
          spacing: DesignConstants.spacingMedium,
          runSpacing: DesignConstants.spacingMedium,
          children: [
            for (final membership in memberships)
              _StatusPill(membership: membership),
          ],
        ),
      ],
    );
  }
}

/// One held membership, named with its status. The FILL carries the meaning;
/// a status with nothing to say (ended, cancelled) takes the plain outlined
/// pill rather than a colour that would imply one.
class _StatusPill extends StatelessWidget {
  final MembershipInfo membership;

  const _StatusPill({required this.membership});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final tone = _toneOf(membership.status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: tone.fill ?? DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: tone.fill == null
            ? Border.all(color: DesignConstants.line)
            : null,
      ),
      child: Text(
        '${membership.planName} · ${membership.status.displayLabel}',
        style: scale.tag.copyWith(color: tone.ink),
      ),
    );
  }
}

/// Live and paid reads green; paused reads cool; behind reads warm; over reads
/// as nothing at all.
({Color? fill, Color ink}) _toneOf(MembershipStatus status) => switch (status) {
      MembershipStatus.active || MembershipStatus.trial => (
          fill: DesignConstants.greenDark,
          ink: DesignConstants.goodGreen,
        ),
      MembershipStatus.frozen || MembershipStatus.dormant => (
          fill: DesignConstants.blueDark,
          ink: DesignConstants.primaryColor,
        ),
      MembershipStatus.overdue => (
          fill: DesignConstants.yellowDark,
          ink: DesignConstants.okYellow,
        ),
      _ => (fill: null, ink: DesignConstants.text2nd),
    };
