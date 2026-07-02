import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/check_in/presentation/widgets/check_in_dialog_actions.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/batch_check_in_picker.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/batch_check_in_results_view.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

enum _Phase { select, processing, results }

/// Batch staff check-in ("Update attendees") for one class occurrence: pick
/// members → submit (207) → a per-member results step (each row shows ✓ checked
/// in / already in / needs confirmation / ✗ failed, plus any non-blocking
/// warnings). A `needs_confirmation` member was NOT recorded — the results step
/// offers "Check in the remaining N anyway", which resubmits just that subset
/// with `ignoreWarnings: true` and merges the (partial) response back into the
/// full breakdown. Shares the board's [ScheduleBloc] (a successful run reloads
/// the week).
class ClassBatchCheckInDialog extends StatefulWidget {
  final String classId;
  final String gymId;
  final String className;

  /// The occurrence's IDENTITY date (never its effective/display date) —
  /// this addresses the batch check-in.
  final DateTime occurrenceDate;

  /// The occurrence's IDENTITY time — the other half of its identity key
  /// (several slots per day are legal).
  final String occurrenceTime;

  const ClassBatchCheckInDialog({
    super.key,
    required this.classId,
    required this.gymId,
    required this.className,
    required this.occurrenceDate,
    required this.occurrenceTime,
  });

  static Future<void> show({
    required BuildContext context,
    required String classId,
    required String gymId,
    required String className,
    required DateTime occurrenceDate,
    required String occurrenceTime,
  }) {
    final bloc = context.read<ScheduleBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<ScheduleBloc>.value(
        value: bloc,
        child: ClassBatchCheckInDialog(
          classId: classId,
          gymId: gymId,
          className: className,
          occurrenceDate: occurrenceDate,
          occurrenceTime: occurrenceTime,
        ),
      ),
    );
  }

  @override
  State<ClassBatchCheckInDialog> createState() =>
      _ClassBatchCheckInDialogState();
}

class _ClassBatchCheckInDialogState extends State<ClassBatchCheckInDialog> {
  _Phase _phase = _Phase.select;
  final Set<String> _selectedIds = {};
  final Map<String, String> _names = {};
  String? _inlineError;

  /// True while the in-flight request is a "Check in anyway" confirmation
  /// retry (as opposed to the initial pick-step submit) — decides whether a
  /// transport failure returns to the picker (fresh submit) or stays on the
  /// results step (retry, so the already-rendered breakdown isn't lost).
  bool _confirmingWarnings = false;

  @override
  void initState() {
    super.initState();
    context.read<ScheduleBloc>().add(const ScheduleBatchCheckInCleared());
  }

  void _toggle(MemberPickerEntry entry) {
    setState(() {
      _inlineError = null;
      if (_selectedIds.add(entry.id)) {
        _names[entry.id] = entry.name;
      } else {
        _selectedIds.remove(entry.id);
        _names.remove(entry.id);
      }
    });
  }

  void _submit(List<String> ids) {
    if (ids.isEmpty) return;
    _confirmingWarnings = false;
    setState(() => _phase = _Phase.processing);
    context.read<ScheduleBloc>().add(ScheduleBatchCheckInRequested(
          classId: widget.classId,
          occurrenceDate: widget.occurrenceDate,
          occurrenceTime: widget.occurrenceTime,
          memberIds: ids,
        ));
  }

  /// "Check in the remaining N anyway": resubmit just the `needsConfirmation`
  /// subset with `ignoreWarnings: true`.
  void _confirmWarnings(List<String> ids) {
    if (ids.isEmpty) return;
    _confirmingWarnings = true;
    setState(() {
      _phase = _Phase.processing;
      _inlineError = null;
    });
    context.read<ScheduleBloc>().add(ScheduleBatchCheckInRequested(
          classId: widget.classId,
          occurrenceDate: widget.occurrenceDate,
          occurrenceTime: widget.occurrenceTime,
          memberIds: ids,
          ignoreWarnings: true,
        ));
  }

  void _onState(BuildContext context, ScheduleState state) {
    if (_phase != _Phase.processing) return;
    if (state is! ScheduleLoaded || state.isCheckingIn) return;
    if (state.batchCheckInResult != null) {
      setState(() {
        _phase = _Phase.results;
        _inlineError = null;
      });
    } else if (state.checkInError != null) {
      setState(() {
        // A confirmation retry's failure stays on the results step (the prior
        // breakdown is still valid and shouldn't disappear); a fresh submit's
        // failure returns to the picker.
        _phase = _confirmingWarnings ? _Phase.results : _Phase.select;
        _inlineError = state.checkInError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ScheduleBloc, ScheduleState>(
      listener: _onState,
      child: switch (_phase) {
        _Phase.processing => const AppDialog(
            title: 'Update attendees',
            body: CheckInProcessingView(),
          ),
        _Phase.results => AppDialog(
            title: 'Update attendees',
            body: BatchCheckInResultsView(
              memberNames: _names,
              onConfirmWarnings: _confirmWarnings,
              inlineError: _inlineError,
            ),
            actions: checkInDoneActions(context),
          ),
        _Phase.select => AppDialog(
            title: 'Update attendees',
            body: BatchCheckInPicker(
              gymId: widget.gymId,
              description: 'Pick the members who attended this '
                  '${widget.className}, then check them in together.',
              selectedIds: _selectedIds,
              inlineError: _inlineError,
              onToggle: _toggle,
            ),
            actions: checkInChoiceActions(
              primaryLabel: _selectedIds.isEmpty
                  ? 'Check in'
                  : 'Check in ${_selectedIds.length}',
              onPrimary: _selectedIds.isEmpty
                  ? null
                  : () => _submit(_selectedIds.toList()),
              dismissLabel: 'Cancel',
            ),
          ),
      },
    );
  }
}
