import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';

/// Profile header with avatar, name, membership label,
/// paid badge, and action buttons.
class ProfileHeaderSection extends StatelessWidget {
  final MemberDetailResponse member;

  const ProfileHeaderSection({
    super.key,
    required this.member,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(
          height: DesignConstants.spacingSmall,
        ),
        // Avatar
        Semantics(
          label: 'Profile photo of ${member.fullName}',
          child: CircleAvatar(
            radius: 120.0 / 2,
            backgroundColor: DesignConstants.backgroundColor,
            backgroundImage: member.photoUrl != null
                ? NetworkImage(member.photoUrl!)
                : null,
            child: member.photoUrl == null
                ? const Icon(
                    Icons.person,
                    size: 120.0 / 2,
                    color: DesignConstants.text,
                  )
                : null,
          ),
        ),
        const SizedBox(
          height: DesignConstants.spacingSmall,
        ),
        // Name
        Text(
          member.fullName,
          style: DesignConstants.h1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(
          height: DesignConstants.spacingTiny,
        ),
        // Membership label + paid badge
        _MembershipLabelRow(member: member),
        const SizedBox(
          height: DesignConstants.spacingMedium,
        ),
        // Action buttons
        _ActionButtonsRow(),
        const SizedBox(
          height: DesignConstants.spacingLarge,
        ),
      ],
    );
  }
}

class _MembershipLabelRow extends StatelessWidget {
  final MemberDetailResponse member;

  const _MembershipLabelRow({required this.member});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            member.membership.displayName,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.primaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (member.isPaid) ...[
          const SizedBox(
            width:
                DesignConstants.spacingSmall,
          ),
          Semantics(
            label: 'Membership payment status: Paid',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal:
                    DesignConstants.spacingSmall,
                vertical:
                    DesignConstants.spacingTiny,
              ),
              decoration: BoxDecoration(
                color: DesignConstants.primaryColor,
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusBig,
                ),
              ),
              child: Text(
                'Paid',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _actionButton('Check In', onPressed: () {}),
        const SizedBox(
          width: DesignConstants.spacingMedium,
        ),
        _actionButton('Charge Card', onPressed: () {}),
        const SizedBox(
          width: DesignConstants.spacingMedium,
        ),
        _actionButton('Edit', onPressed: () {}),
      ],
    );
  }

  Widget _actionButton(
    String label, {
    VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: DesignConstants.text,
        side: const BorderSide(
          color: DesignConstants.buttonStroke,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        minimumSize: Size(
          100.0,
          36,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal:
              DesignConstants.spacingLarge,
          vertical:
              DesignConstants.spacingSmall,
        ),
      ),
      child: Text(label, style: DesignConstants.h3),
    );
  }
}
