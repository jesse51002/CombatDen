import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/models/class_range_exception.dart';
import 'package:crm/features/schedule/data/range_exception_helpers.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/features/schedule/presentation/dialogs/class_range_dates_dialog.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_cancelled_range_row.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// The class form's (edit mode only) "Cancelled ranges" section: every CANCEL
/// range exception on this class whose `end_date` is today or later — the
/// class's present/future cancellations, per row "start – end" with Edit /
/// Remove. Hidden entirely while empty (no cancelled ranges, or none still
/// present/future).
///
/// A self-contained side read (mirrors `ClassAttendeeRoster`'s own-repository
/// pattern) — no schedule bloc state of its own. Edit/Remove DO dispatch
/// through the shared [ScheduleBloc] (`ScheduleRangeExceptionUpdated` /
/// `ScheduleRangeExceptionDeleted`) so the board reloads consistently with
/// every other schedule mutation; this section also refetches its own list on
/// ANY bloc mutation success (a "Cancel a date range" from the form's other
/// secondary action creates a new row here too), and shows a per-row spinner
/// + SnackBar confirmation for its own edit/remove, mirroring the roster's
/// confirm → mutate → SnackBar shape — never a silent dismiss.
class ClassCancelledRangesSection extends StatefulWidget {
  final String classId;
  final String className;

  const ClassCancelledRangesSection({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassCancelledRangesSection> createState() =>
      _ClassCancelledRangesSectionState();
}

class _ClassCancelledRangesSectionState
    extends State<ClassCancelledRangesSection> {
  final ScheduleRepository _repository =
      ScheduleRepository(apiClient: ApiClient());
  late Future<List<ClassRangeException>> _future = _fetch();

  /// The row currently mid-mutation (drives that row's spinner); null when
  /// nothing of this section's own is in flight.
  String? _pendingExceptionId;
  int _successBaseline = 0;
  String? _pendingSuccessMessage;
  String? _pendingErrorMessage;

  Future<List<ClassRangeException>> _fetch() async {
    final ranges = await _repository.listRangeExceptions(widget.classId);
    final today = _dateOnly(DateTime.now());
    return ranges
        .where((r) => r.isCancelled && !r.endDate.isBefore(today))
        .toList();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _refetch() => setState(() => _future = _fetch());

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _edit(ClassRangeException range) async {
    final picked = await ClassRangeDatesDialog.show(
      context: context,
      className: widget.className,
      initialStart: range.startDate,
      initialEnd: range.endDate,
    );
    if (picked == null || !mounted) return;
    final (start, end) = picked;
    if (rangeWidensCoverage(
      oldStart: range.startDate,
      oldEnd: range.endDate,
      newStart: start,
      newEnd: end,
    )) {
      final confirmed = await ConfirmationModal.show(
        context: context,
        title: kRangeEditWidenTitle,
        message: kRangeEditWidenMessage,
        confirmLabel: kRangeEditWidenConfirmLabel,
        confirmColor: DesignConstants.badRed,
      );
      if (!confirmed || !mounted) return;
    }
    _dispatch(
      range.exceptionId,
      ScheduleRangeExceptionUpdated(
        classId: widget.classId,
        exceptionId: range.exceptionId,
        start: start,
        end: end,
      ),
      successMessage: 'Range updated.',
      errorMessage: 'Couldn\'t update the range. Try again.',
    );
  }

  Future<void> _remove(ClassRangeException range) async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: kRangeRemoveTitle,
      message: kRangeRemoveMessage,
      confirmLabel: kRangeRemoveConfirmLabel,
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    _dispatch(
      range.exceptionId,
      ScheduleRangeExceptionDeleted(
        classId: widget.classId,
        exceptionId: range.exceptionId,
      ),
      successMessage: 'Range removed. Its dates are back on the schedule.',
      errorMessage: 'Couldn\'t remove the range. Try again.',
    );
  }

  void _dispatch(
    String exceptionId,
    ScheduleEvent event, {
    required String successMessage,
    required String errorMessage,
  }) {
    final bloc = context.read<ScheduleBloc>();
    final state = bloc.state;
    setState(() {
      _pendingExceptionId = exceptionId;
      _successBaseline = state is ScheduleLoaded ? state.actionSuccessCount : 0;
      _pendingSuccessMessage = successMessage;
      _pendingErrorMessage = errorMessage;
    });
    bloc.add(event);
  }

  /// Reacts to ANY schedule mutation success (not just this section's own —
  /// the form's "Cancel a date range" secondary action creates a new row
  /// here too) by refetching; only shows this section's own toast when it
  /// was the one that dispatched.
  void _onBlocState(BuildContext context, ScheduleState state) {
    if (state is! ScheduleLoaded || state.isMutating) return;
    final ownPending = _pendingExceptionId != null;
    if (state.actionSuccessCount > _successBaseline) {
      _successBaseline = state.actionSuccessCount;
      _refetch();
      if (ownPending) {
        final message = _pendingSuccessMessage;
        setState(() {
          _pendingExceptionId = null;
          _pendingSuccessMessage = null;
          _pendingErrorMessage = null;
        });
        if (message != null) _toast(message);
      }
    } else if (ownPending && state.actionError != null) {
      final message = _pendingErrorMessage ?? 'Something went wrong. Try again.';
      setState(() {
        _pendingExceptionId = null;
        _pendingSuccessMessage = null;
        _pendingErrorMessage = null;
      });
      _toast(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ScheduleBloc, ScheduleState>(
      listener: _onBlocState,
      child: FutureBuilder<List<ClassRangeException>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            // Quiet while loading -- a form-load side read, not worth a
            // dedicated spinner shell that would jump the layout once it
            // resolves (usually empty).
            return const SizedBox.shrink();
          }
          final ranges = snapshot.data ?? const [];
          if (snapshot.hasError || ranges.isEmpty) {
            return const SizedBox.shrink();
          }
          return SubtitleSection(
            title: 'Cancelled ranges',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                for (final range in ranges)
                  ClassCancelledRangeRow(
                    key: ValueKey(range.exceptionId),
                    range: range,
                    isPending: _pendingExceptionId == range.exceptionId,
                    onEdit: () => _edit(range),
                    onRemove: () => _remove(range),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
