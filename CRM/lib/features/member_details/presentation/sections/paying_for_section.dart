import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// The covered people on the current membership and their
/// class usage for the cycle. Each row can navigate to that
/// member via [onLinkedAccountTap].
class PayingForSection extends StatelessWidget {
  final MembershipInfo membership;
  final ValueChanged<String>? onLinkedAccountTap;

  const PayingForSection({
    super.key,
    required this.membership,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Paying membership for',
      child: AppDataTable(
        shrinkWrap: true,
        stickyHeader: false,
        columns: const [
          AppDataTableColumn(label: 'Name', fill: true),
          AppDataTableColumn(label: 'Usage', minWidth: 140),
        ],
        rows: membership.payingFor
            .map((a) => _row(a))
            .toList(),
      ),
    );
  }

  AppDataTableRow _row(PayingForMember account) {
    return AppDataTableRow(
      onTap: onLinkedAccountTap != null
          ? () => onLinkedAccountTap!(account.memberId)
          : null,
      cells: [
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            CircleAvatar(
              radius: DesignConstants.iconSizeSmall,
              backgroundColor: DesignConstants.backgroundColor,
              backgroundImage: account.photoUrl != null
                  ? NetworkImage(account.photoUrl!)
                  : null,
              child: account.photoUrl == null
                  ? Text(
                      account.firstName.isNotEmpty
                          ? account.firstName[0]
                              .toUpperCase()
                          : '?',
                      style: DesignConstants.pSmall.copyWith(
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
    if (!isTerminalStatus(membership.status)) {
      final exit = membership.exitDateFor(account.memberId);
      if (exit != null) {
        buffer.write(' ${_exitLabel(exit)}');
      }
    }
    return buffer.toString();
  }

  String _exitLabel(MembershipExitDate exit) {
    final verb =
        exit.kind == MembershipExitKind.cancelling
            ? 'cancelling'
            : 'ending';
    return '($verb ${formatShortDay(exit.date)})';
  }

  TextStyle _nameStyle(MembershipStatus status) {
    return switch (status) {
      MembershipStatus.frozen => DesignConstants.h3
          .copyWith(color: DesignConstants.okYellow),
      MembershipStatus.cancelled => DesignConstants.h3
          .copyWith(color: DesignConstants.badRed),
      MembershipStatus.ended => DesignConstants.h3
          .copyWith(color: DesignConstants.badRed),
      MembershipStatus.overdue => DesignConstants.h3
          .copyWith(color: DesignConstants.badRed),
      _ => DesignConstants.h3,
    };
  }

  String _usageText(PayingForMember account) {
    if (account.classCount == null) {
      final cycle = membership.durationUnit.toLowerCase();
      return '${account.classesUsed} classes this $cycle';
    }
    return '${account.classesUsed}/'
        '${account.classCount} classes';
  }
}
