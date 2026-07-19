import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/existing_member_pill.dart';
import 'package:crm/shared/widgets/member_identity_card.dart';

/// One member in the add-member group roster: avatar + name + email, mirroring
/// the confirmation identity card. Trailing marks an [ExistingMemberPill] for a
/// kept duplicate and an "Added" flash on the [isLast] (just-added) row. No
/// per-row removal — the group is append-only.
class GroupRosterRow extends StatelessWidget {
  final String name;
  final String? email;
  final String? photoUrl;
  final bool wasExisting;
  final bool isLast;

  const GroupRosterRow({
    super.key,
    required this.name,
    required this.wasExisting,
    required this.isLast,
    this.email,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return MemberIdentityCard(
      name: name,
      email: email,
      photoUrl: photoUrl,
      trailing: _Trailing(wasExisting: wasExisting, isLast: isLast),
    );
  }
}

class _Trailing extends StatelessWidget {
  final bool wasExisting;
  final bool isLast;

  const _Trailing({required this.wasExisting, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (wasExisting) const ExistingMemberPill(),
        if (isLast)
          Text(
            'Added',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.goodGreen,
            ),
          ),
      ],
    );
  }
}
