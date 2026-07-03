import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/home/data/live_attendance_section.dart';
import 'package:crm/features/home/presentation/widgets/live_attendance_card/live_attendance_status_pill.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_name_cell.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/attendee_list_response.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// The card's roster: one labelled block per shown occurrence (usually one;
/// several when classes overlap), each a class-name sub-header over the
/// combined signed-up ∪ attended member table. Rows deep-link to the
/// member's detail page.
class LiveAttendanceRoster extends StatelessWidget {
  final List<LiveAttendanceSection> sections;

  /// True when the shown occurrence is the NEXT class (nothing in session) —
  /// a not-checked-in row then reads "Reserved", not "Not Here".
  final bool isNextPreview;

  const LiveAttendanceRoster({
    super.key,
    required this.sections,
    required this.isNextPreview,
  });

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: Center(
          child: _SecondaryText('No upcoming classes scheduled.'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final section in sections)
          _SectionBlock(section: section, isNextPreview: isNextPreview),
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final LiveAttendanceSection section;
  final bool isNextPreview;

  const _SectionBlock({required this.section, required this.isNextPreview});

  /// `Now · 6:00 PM - 7:00 PM` for an in-session class; the next-class
  /// preview adds the (possibly not-today) date.
  String get _whenLabel {
    final i = section.instance;
    return isNextPreview
        ? 'Next · ${classDateTimeRangeLabel(
            i.classDate,
            i.resolvedClassTime,
            i.resolvedDurationMinutes,
          )}'
        : 'Now · ${classTimeRangeLabel(
            i.resolvedClassTime,
            i.resolvedDurationMinutes,
          )}';
  }

  LiveAttendanceStatus _statusFor(Attendee attendee) {
    if (attendee.attended) return LiveAttendanceStatus.checkedIn;
    return isNextPreview
        ? LiveAttendanceStatus.reserved
        : LiveAttendanceStatus.notHere;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text(section.instance.className, style: DesignConstants.h3),
            _SecondaryText(_whenLabel),
          ],
        ),
        if (section.attendees.isEmpty)
          _SecondaryText(
            isNextPreview
                ? 'No reservations yet.'
                : 'No reservations or check-ins yet.',
          )
        else
          AppDataTable(
            shrinkWrap: true,
            columns: const [
              AppDataTableColumn(label: 'Name', minWidth: 160, fill: true),
              AppDataTableColumn(label: 'Attending', minWidth: 110),
            ],
            rows: [
              for (final attendee in section.attendees)
                AppDataTableRow(
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.memberDetailPath(attendee.memberId),
                  ),
                  cells: [
                    MemberNameCell(name: attendee.fullName),
                    LiveAttendanceStatusPill(status: _statusFor(attendee)),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

class _SecondaryText extends StatelessWidget {
  final String text;

  const _SecondaryText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: DesignConstants.pSmall.copyWith(color: DesignConstants.text2nd),
    );
  }
}
