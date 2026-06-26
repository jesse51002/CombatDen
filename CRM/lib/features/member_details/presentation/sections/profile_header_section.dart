import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/charge_card_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/coming_soon_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/edit_member_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_wizard.dart';
import 'package:crm/features/member_details/presentation/dialogs/unlink_payment_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/update_card_dialog.dart';
import 'package:crm/features/member_details/presentation/sections/linked_accounts_section.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Profile header: avatar, name, membership summary, paid
/// badge, the member-level action row (Check In / Charge
/// Card / Add or Update Card / Start Membership / Edit),
/// and the linked-accounts block.
class ProfileHeaderSection extends StatelessWidget {
  final MemberDetailResponse member;
  final ValueChanged<String>? onLinkedAccountTap;

  const ProfileHeaderSection({
    super.key,
    required this.member,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          _ProfileInfo(
            member: member,
            onLinkedAccountTap: onLinkedAccountTap,
          ),
          LinkedAccountsSection(
            member: member,
            onLinkedAccountTap: onLinkedAccountTap,
          ),
        ],
      ),
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  final MemberDetailResponse member;
  final ValueChanged<String>? onLinkedAccountTap;

  const _ProfileInfo({
    required this.member,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingMedium,
      children: [
        Semantics(
          label: 'Profile photo of ${member.fullName}',
          child: CircleAvatar(
            radius: 64,
            backgroundColor: DesignConstants.backgroundColor,
            backgroundImage: member.photoUrl != null
                ? NetworkImage(member.photoUrl!)
                : null,
            child: member.photoUrl == null
                ? Icon(
                    Symbols.person_sharp,
                    size: DesignConstants.iconSizeBig,
                    color: DesignConstants.text2nd,
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
        _ActionButtonsRow(
          member: member,
          onViewMember: onLinkedAccountTap,
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
      spacing: DesignConstants.spacingSmall,
      children: [
        Flexible(
          child: Semantics(
            label: member.membershipOverview,
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
        if (member.isPaid) const _PaidBadge(),
      ],
    );
  }
}

class _PaidBadge extends StatelessWidget {
  const _PaidBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Membership payment status: Paid',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingSmall,
          vertical: DesignConstants.spacingTiny,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.primaryColor10,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          border: Border.all(
            color: DesignConstants.primaryColor,
          ),
        ),
        child: Text(
          'Paid',
          style: DesignConstants.pSmallBold.copyWith(
            color: DesignConstants.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  final MemberDetailResponse member;

  /// Navigates to another member's detail page — used by
  /// the start-memberships results step's "view member"
  /// affordance.
  final ValueChanged<String>? onViewMember;

  const _ActionButtonsRow({
    required this.member,
    this.onViewMember,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFrozen = member.memberships.any(
      (m) => m.status == MembershipStatus.frozen,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        _ActionButton(
          label: 'Check In',
          onPressed: () => ComingSoonDialog.show(
            context: context,
            title: 'Check In',
            message:
                'Class check-in is pending the classes '
                'feature on the backend.',
          ),
        ),
        _ActionButton(
          label: 'Charge Card',
          onPressed: () => ChargeCardDialog.show(
            context: context,
            member: member,
          ),
        ),
        _ActionButton(
          label: member.cardOnFile == null
              ? 'Add Card'
              : 'Update Card',
          onPressed: () async {
            final removeRequested =
                await UpdateCardDialog.show(
              context: context,
              memberName: member.fullName,
              card: member.cardOnFile,
            );
            final card = member.cardOnFile;
            if (removeRequested &&
                card != null &&
                context.mounted) {
              await UnlinkPaymentDialog.show(
                context: context,
                memberName: member.fullName,
                cardLabel:
                    '${card.brand} ···· ${card.lastFour}',
              );
            }
          },
        ),
        _ActionButton(
          label: 'Start Membership',
          onPressed: isFrozen
              ? null
              : () => StartMembershipsWizard.show(
                    context: context,
                    member: member,
                    onViewMember: onViewMember,
                  ),
          tooltip: isFrozen
              ? 'Unfreeze this member before adding a membership'
              : null,
        ),
        _ActionButton(
          label: 'Edit',
          onPressed: () => EditMemberDialog.show(
            context: context,
            member: member,
          ),
        ),
      ],
    );
  }

}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// When set, the button is wrapped in a [Tooltip] showing
  /// this message — used to explain why it is disabled.
  final String? tooltip;

  const _ActionButton({
    required this.label,
    this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = AppOutlineButton(
      text: label,
      onPressed: onPressed,
      borderRadius: DesignConstants.radiusSmall,
      textStyle: DesignConstants.h3,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingLarge,
        vertical: DesignConstants.spacingSmall,
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
