import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/charge_card/charge_card_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/coming_soon_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/edit_member/edit_member_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/update_card/update_card_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Avatar, name, membership overview, and action buttons.
class ProfileInfoSection extends StatelessWidget {
  final MemberDetailResponse member;

  const ProfileInfoSection({
    super.key,
    required this.member,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingMedium,
      children: [
        Semantics(
          label: 'Profile photo of ${member.fullName}',
          child: CircleAvatar(
            radius: 75,
            backgroundColor: DesignConstants.card,
            backgroundImage: member.photoUrl != null
                ? NetworkImage(member.photoUrl!)
                : null,
            child: member.photoUrl == null
                ? Icon(
                    Symbols.person_sharp,
                    size: 55,
                    color: DesignConstants.text,
                    weight: DesignConstants.iconWeight,
                  )
                : null,
          ),
        ),
        Text(
          member.fullName,
          style: DesignConstants.h1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        _MembershipLabelRow(member: member),
        _ActionButtonsRow(member: member),
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
      spacing: DesignConstants.spacingSmall,
      children: [
        Flexible(
          child: Semantics(
            label:
                'Paying for ${member.totalMembershipCount}'
                ' memberships',
            child: Text(
              member.membershipOverview,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.primaryColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (member.isPaid)
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
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  final MemberDetailResponse member;

  const _ActionButtonsRow({required this.member});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        _actionButton(
          'Check In',
          onPressed: () => ComingSoonDialog.show(
            context: context,
            title: 'Check In',
            message:
                'Class check-in is pending a classes feature.',
          ),
        ),
        _actionButton(
          'Charge Card',
          onPressed: () => ChargeCardDialog.show(
            context: context,
            member: member,
          ),
        ),
        _actionButton(
          member.cardOnFile == null
              ? 'Add Card'
              : 'Update Card',
          onPressed: () => UpdateCardDialog.show(
            context: context,
            existingCard: member.cardOnFile,
          ),
        ),
        _actionButton(
          'Start Membership',
          onPressed: () => StartMembershipDialog.show(
            context: context,
            member: member,
          ),
        ),
        _actionButton(
          'Edit',
          onPressed: () => EditMemberDialog.show(
            context: context,
            member: member,
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
    String label, {
    VoidCallback? onPressed,
  }) {
    return AppOutlineButton(
      text: label,
      onPressed: onPressed,
      borderRadius: DesignConstants.radiusSmall,
      textStyle: DesignConstants.h3,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingLarge,
        vertical: DesignConstants.spacingSmall,
      ),
    );
  }
}
