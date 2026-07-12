import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/member_identity_card.dart';

/// The add-member flow's confirmation step: a green check, the headline, a
/// reassuring subtitle, and the member's identity card. Offers continuing to
/// memberships or finishing here (a member with no membership is fine).
class AddMemberCreatedView extends StatelessWidget {
  final String name;
  final String? email;
  final String? photoUrl;

  /// True when the flow continued with an existing duplicate rather than
  /// creating a new member — changes the headline wording.
  final bool wasExisting;

  const AddMemberCreatedView({
    super.key,
    required this.name,
    required this.wasExisting,
    this.email,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.goodGreen,
        ),
        Text(
          wasExisting
              ? '$name is already a member'
              : '$name has been added',
          style: DesignConstants.h1,
          textAlign: TextAlign.center,
        ),
        Text(
          'You can set up their membership now, or finish here. A '
          'member with no membership is fine.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
        MemberIdentityCard(
          name: name,
          email: email,
          photoUrl: photoUrl,
        ),
      ],
    );
  }
}
