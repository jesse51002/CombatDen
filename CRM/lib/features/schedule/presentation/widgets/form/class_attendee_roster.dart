import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/schedule/data/models/attendee_list_response.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Read-only roster of the members who attended this occurrence, shown inside
/// the class form's "This session" block for a past / materialized occurrence
/// (today or earlier). A self-contained side fetch (a [FutureBuilder] over its
/// own [ScheduleRepository]) — no schedule bloc — mirroring the batch picker's
/// own-repository pattern. An unmaterialized occurrence (no check-ins yet) and
/// an empty roster both read "No attendees yet."
class ClassAttendeeRoster extends StatefulWidget {
  final String gymId;
  final String classId;
  final DateTime occurrenceDate;

  const ClassAttendeeRoster({
    super.key,
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
  });

  @override
  State<ClassAttendeeRoster> createState() => _ClassAttendeeRosterState();
}

class _ClassAttendeeRosterState extends State<ClassAttendeeRoster> {
  final ScheduleRepository _repository =
      ScheduleRepository(apiClient: ApiClient());
  late final Future<AttendeeListResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.listAttendees(
      widget.gymId,
      widget.classId,
      widget.occurrenceDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('Attendees', style: DesignConstants.pSemibold),
        FutureBuilder<AttendeeListResponse>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(DesignConstants.spacingSmall),
                child: AppSpinner(),
              );
            }
            if (snapshot.hasError) {
              return _Hint('We couldn’t load the attendee list.');
            }
            final attendees = snapshot.data?.attendees ?? const [];
            if (attendees.isEmpty) return _Hint('No attendees yet.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                for (final a in attendees) _AttendeeRow(name: a.fullName),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One attendee name with a person glyph.
class _AttendeeRow extends StatelessWidget {
  final String name;

  const _AttendeeRow({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.person_sharp,
          size: DesignConstants.iconSizeSmall,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text2nd,
        ),
        Expanded(
          child: Text(
            name,
            style: DesignConstants.p,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Secondary-tone hint line (empty / error states).
class _Hint extends StatelessWidget {
  final String message;

  const _Hint(this.message);

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: DesignConstants.pSmall.copyWith(color: DesignConstants.text2nd),
    );
  }
}
