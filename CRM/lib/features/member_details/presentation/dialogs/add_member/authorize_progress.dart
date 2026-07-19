import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/group_member.dart';
import 'package:crm/shared/widgets/member_avatar.dart';

/// A row of small payee avatars tracking the authorize sequence: signed payees
/// read done (full opacity + a green check), the current payee wears an accent
/// ring, and upcoming payees are dimmed.
class AuthorizeProgress extends StatelessWidget {
  final List<GroupMember> payees;
  final Set<String> committedIds;
  final int currentIndex;

  const AuthorizeProgress({
    super.key,
    required this.payees,
    required this.committedIds,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        for (var i = 0; i < payees.length; i++)
          _ProgressAvatar(
            payee: payees[i],
            committed: committedIds.contains(payees[i].memberId),
            current: i == currentIndex,
          ),
      ],
    );
  }
}

class _ProgressAvatar extends StatelessWidget {
  final GroupMember payee;
  final bool committed;
  final bool current;

  const _ProgressAvatar({
    required this.payee,
    required this.committed,
    required this.current,
  });

  String get _state => committed
      ? 'signed'
      : current
          ? 'current'
          : 'upcoming';

  @override
  Widget build(BuildContext context) {
    final avatar = MemberAvatar(
      name: payee.fullName,
      photoUrl: payee.photoUrl,
      size: DesignConstants.iconSizeBig,
    );
    Widget content = avatar;
    if (current) {
      content = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: DesignConstants.primaryColor,
            width: DesignConstants.buttonBorder,
          ),
        ),
        child: avatar,
      );
    } else if (!committed) {
      content = Opacity(opacity: 0.4, child: avatar);
    }
    return Semantics(
      label: '${payee.fullName}, $_state',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          if (committed)
            Positioned(
              right: -DesignConstants.spacingTiny,
              bottom: -DesignConstants.spacingTiny,
              child: Icon(
                Symbols.check_circle_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.goodGreen,
              ),
            ),
        ],
      ),
    );
  }
}
