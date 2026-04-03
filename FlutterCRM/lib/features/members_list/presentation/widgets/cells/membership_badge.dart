import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// A colored pill badge showing membership status and
/// details.
///
/// Colors vary by [MembershipStatus]:
/// - trial/active: green
/// - frozen: blue
/// - cancelled: yellow
/// - overdue: red
class MembershipBadge extends StatelessWidget {
  final MembershipStatus status;
  final String text;

  const MembershipBadge({
    super.key,
    required this.status,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final bg = _colors(status);

    return SizedBox(
      height: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingSmall,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              text,
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.text,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Color _colors(MembershipStatus status) {
    return switch (status) {
      MembershipStatus.trial => DesignConstants.yellowDark,
      MembershipStatus.active => DesignConstants.greenDark,
      MembershipStatus.frozen => DesignConstants.blueDark,
      MembershipStatus.cancelled => DesignConstants.redDark,
      MembershipStatus.ended => DesignConstants.card,
      MembershipStatus.overdue => DesignConstants.purpleDark,
      MembershipStatus.noMembership => DesignConstants.card,
      MembershipStatus.unknown => DesignConstants.card,
    };
  }
}
