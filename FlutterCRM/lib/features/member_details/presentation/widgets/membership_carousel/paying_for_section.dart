import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:intl/intl.dart';

import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Section showing linked accounts the member pays for.
class PayingForSection extends StatelessWidget {
  final MembershipInfo membership;
  final void Function(String crmUserId)?
      onLinkedAccountTap;

  const PayingForSection({
    super.key,
    required this.membership,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Paying Membership For',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        constraints: const BoxConstraints(
          maxHeight: 300,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            if (membership.payingFor.isEmpty)
              SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    'No linked accounts',
                    style:
                        DesignConstants.h2.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: AppDataTable(
                    shrinkWrap: true,
                    stickyHeader: false,
                    columns: const [
                      AppDataTableColumn(
                        label: 'Name',
                        fill: true,
                      ),
                      AppDataTableColumn(
                        label: 'Usage',
                        minWidth: 130,
                      ),
                    ],
                    rows: membership.payingFor
                        .map(
                          (a) => _buildRow(a),
                        )
                        .toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  AppDataTableRow _buildRow(PayingForMember account) {
    return AppDataTableRow(
      onTap: onLinkedAccountTap != null
          ? () => onLinkedAccountTap!(account.crmUserId)
          : null,
      cells: [
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundImage: account.photoUrl != null
                  ? NetworkImage(account.photoUrl!)
                  : null,
              backgroundColor: DesignConstants.card,
              child: account.photoUrl == null
                  ? Text(
                      account.firstName[0],
                      style:
                          DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text,
                      ),
                    )
                  : null,
            ),
            Flexible(
              child: Text(
                _displayName(account),
                style: _nameStyle(account.status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          _usageText(account),
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _displayName(PayingForMember account) {
    final buffer = StringBuffer(account.fullName);
    if (account.status != MembershipStatus.active) {
      buffer.write(' (${account.status.displayLabel})');
    }
    final terminal =
        membership.status == MembershipStatus.cancelled ||
            membership.status == MembershipStatus.ended;
    if (!terminal) {
      final exit =
          membership.exitDateFor(account.crmUserId);
      if (exit != null) {
        buffer.write(' ${_exitLabel(exit)}');
      }
    }
    return buffer.toString();
  }

  String _exitLabel(MembershipExitDate exit) {
    final fmt = DateFormat('M/d');
    final verb = exit.kind == MembershipExitKind.cancelling
        ? 'cancelling'
        : 'ending';
    return '($verb ${fmt.format(exit.date.toLocal())})';
  }

  TextStyle _nameStyle(MembershipStatus status) {
    return switch (status) {
      MembershipStatus.frozen => DesignConstants.h3
          .copyWith(color: DesignConstants.okYellow),
      MembershipStatus.cancelled => DesignConstants.h3
          .copyWith(color: DesignConstants.badRed),
      MembershipStatus.ended => DesignConstants.h3
          .copyWith(color: DesignConstants.badRed),
      _ => DesignConstants.h3,
    };
  }

  String _usageText(PayingForMember account) {
    if (account.classCount == null) {
      final cycle = membership.durationUnit.toLowerCase();
      return '${account.classesUsed} classes this'
          ' $cycle';
    }
    return '${account.classesUsed}/'
        '${account.classCount} classes';
  }
}
