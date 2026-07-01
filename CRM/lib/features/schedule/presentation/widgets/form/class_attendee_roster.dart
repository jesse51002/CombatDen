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
import 'package:crm/shared/widgets/view_switcher.dart';

/// Max height the scrollable participant list grows to before it scrolls
/// internally — the parent form scrolls too, so the inner list stays bounded.
const double _kMaxRosterHeight = 280;

/// Which of the roster's lists is showing. Order matches display order —
/// Attended first (when it exists at all), Reserved second.
enum _RosterTab { attended, reserved }

/// Searchable, scrollable roster — **Attended** (everyone with a
/// `member_attendance` row) and **Reserved** (everyone with a
/// `class_signups` row for this occurrence) — shown inside the class form's
/// "This session" block for a past / materialized occurrence (today or
/// earlier). A self-contained side fetch (a [FutureBuilder] over its own
/// [ScheduleRepository]) — no schedule bloc — mirroring the batch picker's
/// own-repository pattern. An unmaterialized occurrence with no sign-ups
/// either and an empty roster both read "No attendees yet."
///
/// The **Attended** tab only exists once someone has attended — with no
/// attendance recorded yet, the roster skips the two-tab switcher entirely
/// and renders the **Reserved** list directly (its own count standing in for
/// the switcher). Once the occurrence has ≥1 attended entry, both tabs show
/// — **Attended first, Reserved second** — and the view defaults to
/// Attended. A reserved member who has also attended is marked with a green
/// check + "attended" caption on their Reserved row too (driven by
/// [Attendee.attended]), so a no-show reads differently from someone who
/// showed up; the Attended tab needs no such mark since every row there is
/// attended by definition.
///
/// A member can appear on both tabs (reserved AND attended) — which tab a
/// row is on determines what its remove (×) does, not the member's own
/// [Attendee.attended] flag: a **Reserved** row's removal cancels the
/// reservation (`DELETE /api/v1/signup`); an **Attended** row's removal
/// reverses the check-in (`DELETE /api/v1/checkin`). Tapping it confirms,
/// then on success refetches the roster and surfaces a SnackBar; on failure
/// surfaces an error SnackBar. Never a silent dismiss.
///
/// Once the Attended tab exists, the view defaults to it, then stays on
/// whatever the staff member picked across a refetch — an action on one row
/// shouldn't snap the view back to the default tab.
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

  /// The staff member's explicit tab pick; null means "use the default"
  /// (Attended once it exists, otherwise the Reserved-only view — see class
  /// doc). Left null by the default itself so a refetch that removes the
  /// last attended entry falls back to Reserved automatically.
  _RosterTab? _tab;

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

  void _refetch() => setState(() => _future = _fetch());

  /// **Reserved** row removal — cancels [attendee]'s reservation for this
  /// occurrence, regardless of whether they also attended.
  Future<void> _cancelReservation(Attendee attendee) async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Cancel reservation?',
      message: 'Cancel ${attendee.fullName}’s reservation for this class?',
      confirmLabel: 'Cancel reservation',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    try {
      await _repository.cancelSignup(
        widget.gymId,
        widget.classId,
        widget.occurrenceDate,
        attendee.memberId,
      );
      if (!mounted) return;
      _refetch();
      _toast('Reservation cancelled');
    } catch (_) {
      if (!mounted) return;
      _toast('Couldn’t cancel ${attendee.fullName}’s reservation. Try again.');
    }
  }

  /// **Attended** row removal — reverses [attendee]'s check-in for this
  /// occurrence, regardless of whether they're also still reserved.
  Future<void> _removeCheckIn(Attendee attendee) async {
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
      _refetch();
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
        final reserved = attendees.where((a) => a.signedUp).toList();
        final attended = attendees.where((a) => a.attended).toList();
        final hasAttended = attended.isNotEmpty;
        // The Attended tab (and the switcher itself) only exists once
        // someone has attended; while it does, default to Attended unless
        // the staff member explicitly picked a tab. Recomputed every build
        // (not "picked once") so a refetch that drops the last attended
        // entry falls back to the Reserved-only view automatically.
        final tab = hasAttended ? (_tab ?? _RosterTab.attended) : _RosterTab.reserved;
        return _TabbedRoster(
          reserved: reserved,
          attended: attended,
          hasAttended: hasAttended,
          tab: tab,
          onTabChanged: (tab) => setState(() => _tab = tab),
          onCancelReservation: _cancelReservation,
          onRemoveCheckIn: _removeCheckIn,
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

/// The loaded roster: a header, then either the Attended/Reserved
/// [ViewSwitcher] (each label carrying its count, Attended first — only once
/// [hasAttended]) or, before anyone has attended, just the Reserved list's
/// own count where the switcher would sit; a name search scoped to the
/// active tab, and the bounded, scrollable list of matching participants.
class _TabbedRoster extends StatefulWidget {
  final List<Attendee> reserved;
  final List<Attendee> attended;

  /// Whether the Attended tab exists at all (≥1 attended entry). When false
  /// [tab] is always [_RosterTab.reserved] and no switcher renders.
  final bool hasAttended;
  final _RosterTab tab;
  final ValueChanged<_RosterTab> onTabChanged;
  final ValueChanged<Attendee> onCancelReservation;
  final ValueChanged<Attendee> onRemoveCheckIn;

  const _TabbedRoster({
    required this.reserved,
    required this.attended,
    required this.hasAttended,
    required this.tab,
    required this.onTabChanged,
    required this.onCancelReservation,
    required this.onRemoveCheckIn,
  });

  @override
  State<_TabbedRoster> createState() => _TabbedRosterState();
}

class _TabbedRosterState extends State<_TabbedRoster> {
  String _query = '';

  List<Attendee> get _activeList =>
      widget.tab == _RosterTab.reserved ? widget.reserved : widget.attended;

  List<Attendee> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = _activeList;
    if (q.isEmpty) return list;
    return list.where((a) => a.fullName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final onRemove = widget.tab == _RosterTab.reserved
        ? widget.onCancelReservation
        : widget.onRemoveCheckIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('Attendees', style: DesignConstants.pSemibold),
        // Always the same switcher chrome — two tabs (Attended first) once
        // anyone has attended, otherwise just the single "Reserved" tab so a
        // future / no-attendance occurrence still reads as the same selector.
        ViewSwitcher(
          labels: widget.hasAttended
              ? [
                  'Attended (${widget.attended.length})',
                  'Reserved (${widget.reserved.length})',
                ]
              : ['Reserved (${widget.reserved.length})'],
          selectedIndex: widget.hasAttended
              ? (widget.tab == _RosterTab.attended ? 0 : 1)
              : 0,
          onSelected: (i) => widget.onTabChanged(
            widget.hasAttended && i == 0
                ? _RosterTab.attended
                : _RosterTab.reserved,
          ),
        ),
        AppSearchBox(
          hintText: 'Search participants…',
          onChanged: (value) => setState(() => _query = value),
        ),
        if (filtered.isEmpty)
          _Hint(
            _activeList.isEmpty
                ? (widget.tab == _RosterTab.reserved
                    ? 'No one has reserved a spot yet.'
                    : 'No one has attended yet.')
                : 'No participants match “${_query.trim()}”.',
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _kMaxRosterHeight),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: filtered.length,
              // A full-width divider between rows so a name and its remove (×)
              // stay visually linked across the wide screen.
              separatorBuilder: (_, _) => Divider(
                height: DesignConstants.spacingMedium,
                thickness: DesignConstants.dividerThickness,
                color: DesignConstants.divider,
              ),
              itemBuilder: (context, i) {
                final attendee = filtered[i];
                // The Attended tab is attended by definition — only the
                // Reserved tab needs the mark, to tell a reserved-and-showed
                // member apart from a no-show.
                final showAttendedMark =
                    widget.tab == _RosterTab.reserved && attendee.attended;
                return MemberRowTile(
                  name: attendee.fullName,
                  subtitle: showAttendedMark ? const _AttendedMark() : null,
                  trailing: _RemoveButton(
                    name: attendee.fullName,
                    tab: widget.tab,
                    onPressed: () => onRemove(attendee),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Remove (×) action on one roster row — a staff correction that cancels the
/// reservation (Reserved tab) or reverses the check-in (Attended tab),
/// whichever tab the row is showing on.
class _RemoveButton extends StatelessWidget {
  final String name;
  final _RosterTab tab;
  final VoidCallback onPressed;

  const _RemoveButton({
    required this.name,
    required this.tab,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tab == _RosterTab.reserved
          ? 'Cancel $name’s reservation'
          : 'Remove $name from this class',
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

/// Small green check + "attended" caption shown under a Reserved-tab row
/// whose member also has an attendance record, so a no-show reads
/// differently from someone who showed up. Rendered via
/// [MemberRowTile.subtitle].
class _AttendedMark extends StatelessWidget {
  const _AttendedMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          size: DesignConstants.iconSizeTiny,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.goodGreen,
        ),
        Text(
          'attended',
          style:
              DesignConstants.pSmall.copyWith(color: DesignConstants.goodGreen),
        ),
      ],
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
