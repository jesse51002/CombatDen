import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/home/data/mock_attendance.dart';
import 'package:app_management/shared/widgets/app_data_table.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// Left-hand panel under the hero card: live class roster with a
/// "Check In Member" / "View all" footer.
class LiveAttendanceCard extends StatelessWidget {
  final List<AttendanceEntry> entries;

  const LiveAttendanceCard({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final checkedIn = entries.where((e) => e.checkedIn).length;
    final notArrived = entries.length - checkedIn;
    final percent = entries.isEmpty
        ? 0
        : ((checkedIn / entries.length) * 100).round();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          _Header(
            checkedIn: checkedIn,
            notArrived: notArrived,
            percent: percent,
          ),
          _AttendanceTable(entries: entries),
          _Footer(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int checkedIn;
  final int notArrived;
  final int percent;

  const _Header({
    required this.checkedIn,
    required this.notArrived,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Live Attendance', style: DesignConstants.h1),
        Text(
          '$checkedIn checked in, $notArrived not arrived ($percent% attendance)',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _AttendanceTable extends StatelessWidget {
  final List<AttendanceEntry> entries;
  const _AttendanceTable({required this.entries});

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      shrinkWrap: true,
      columns: const [
        AppDataTableColumn(label: 'Name', minWidth: 160, fill: true),
        AppDataTableColumn(label: 'Attending', minWidth: 110),
      ],
      rows: [
        for (final entry in entries)
          AppDataTableRow(
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.memberDetail),
            cells: [
              _NameCell(entry: entry),
              _StatusPill(checkedIn: entry.checkedIn),
            ],
          ),
      ],
    );
  }
}

class _NameCell extends StatelessWidget {
  final AttendanceEntry entry;
  const _NameCell({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        ClipOval(
          child: Image.asset(
            entry.avatarAsset,
            width: 30,
            height: 30,
            fit: BoxFit.cover,
          ),
        ),
        Expanded(
          child: Text(
            entry.fullName,
            overflow: TextOverflow.ellipsis,
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small status indicator at the right of an attendance row —
/// a colored vertical bar plus "Checked In" / "Not Here" text.
class _StatusPill extends StatelessWidget {
  final bool checkedIn;
  const _StatusPill({required this.checkedIn});

  @override
  Widget build(BuildContext context) {
    final color = checkedIn
        ? DesignConstants.goodGreen
        : DesignConstants.badRed;
    final label = checkedIn ? 'Checked In' : 'Not Here';

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Container(
          width: 5,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          ),
        ),
        Text(label, style: DesignConstants.h3.copyWith(color: color)),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          child: AppPrimaryButton(
            text: 'Check In Member',
            fullWidth: true,
            onPressed: () =>
                debugPrint('TODO: wire Check In Member action'),
          ),
        ),
        Expanded(
          child: AppOutlineButton(
            text: 'View all',
            fullWidth: true,
            onPressed: () =>
                debugPrint('TODO: wire View all attendance action'),
          ),
        ),
      ],
    );
  }
}
