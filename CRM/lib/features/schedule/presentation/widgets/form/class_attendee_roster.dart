import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/schedule/data/models/attendee_list_response.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/member_row_tile.dart';

/// Max height the scrollable participant list grows to before it scrolls
/// internally — the parent form scrolls too, so the inner list stays bounded.
const double _kMaxRosterHeight = 280;

/// Searchable, scrollable roster of the members on this occurrence. Shown inside
/// the class form's "This session" block for a past / materialized occurrence
/// (today or earlier). A self-contained side fetch (a [FutureBuilder] over its
/// own [ScheduleRepository]) — no schedule bloc — mirroring the batch picker's
/// own-repository pattern. An unmaterialized occurrence (no check-ins yet) and
/// an empty roster both read "No attendees yet."
///
/// Each row also carries a remove (×) action — a staff correction that
/// reverses the member's check-in (`DELETE /api/v1/checkin`). Tapping it
/// confirms, then on success refetches the roster and surfaces a SnackBar;
/// on failure surfaces an error SnackBar. Never a silent dismiss.
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
  late Future<AttendeeListResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<AttendeeListResponse> _fetch() => _repository.listAttendees(
        widget.gymId,
        widget.classId,
        widget.occurrenceDate,
      );

  Future<void> _removeAttendee(Attendee attendee) async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Remove attendee?',
      message: 'Remove ${attendee.fullName} from this class?',
      confirmLabel: 'Remove',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    try {
      await _repository.removeAttendee(
        widget.gymId,
        widget.classId,
        widget.occurrenceDate,
        attendee.memberId,
      );
      if (!mounted) return;
      setState(() => _future = _fetch());
      _toast('Removed from class');
    } catch (_) {
      if (!mounted) return;
      _toast('Couldn’t remove ${attendee.fullName}. Try again.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AttendeeListResponse>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _Framed(
            child: const Padding(
              padding: EdgeInsets.all(DesignConstants.spacingSmall),
              child: AppSpinner(),
            ),
          );
        }
        if (snapshot.hasError) {
          return _Framed(child: _Hint('We couldn’t load the attendee list.'));
        }
        final attendees = snapshot.data?.attendees ?? const [];
        if (attendees.isEmpty) {
          return _Framed(child: _Hint('No attendees yet.'));
        }
        return _AttendeeList(
          attendees: attendees,
          onRemove: _removeAttendee,
        );
      },
    );
  }
}

/// "Attendees" header above a body — the loading / error / empty shell.
class _Framed extends StatelessWidget {
  final Widget child;

  const _Framed({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('Attendees', style: DesignConstants.pSemibold),
        child,
      ],
    );
  }
}

/// The loaded roster: a count header, a name search, and the bounded,
/// scrollable list of matching participants.
class _AttendeeList extends StatefulWidget {
  final List<Attendee> attendees;
  final ValueChanged<Attendee> onRemove;

  const _AttendeeList({required this.attendees, required this.onRemove});

  @override
  State<_AttendeeList> createState() => _AttendeeListState();
}

class _AttendeeListState extends State<_AttendeeList> {
  String _query = '';

  List<Attendee> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.attendees;
    return widget.attendees
        .where((a) => a.fullName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Attendees (${widget.attendees.length})',
          style: DesignConstants.pSemibold,
        ),
        AppSearchBox(
          hintText: 'Search participants…',
          onChanged: (value) => setState(() => _query = value),
        ),
        if (filtered.isEmpty)
          _Hint('No participants match “${_query.trim()}”.')
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _kMaxRosterHeight),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: filtered.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: DesignConstants.spacingSmall),
              itemBuilder: (context, i) {
                final attendee = filtered[i];
                return MemberRowTile(
                  name: attendee.fullName,
                  trailing: _RemoveAttendeeButton(
                    name: attendee.fullName,
                    onPressed: () => widget.onRemove(attendee),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Remove (×) action on one attendee row — a staff correction that reverses
/// the member's check-in.
class _RemoveAttendeeButton extends StatelessWidget {
  final String name;
  final VoidCallback onPressed;

  const _RemoveAttendeeButton({required this.name, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Remove $name from this class',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(
        Symbols.close_sharp,
        size: DesignConstants.iconSizeSmall,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.badRed,
      ),
    );
  }
}

/// Secondary-tone hint line (empty / error / no-match states).
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
