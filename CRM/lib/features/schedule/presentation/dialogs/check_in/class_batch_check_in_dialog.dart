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
/// in / already in / ✗ failed, plus any non-blocking warnings). Staff always
/// records, so there is no "check in anyway" retry. Shares the board's
/// [ScheduleBloc] (a successful run reloads the week).
class ClassBatchCheckInDialog extends StatefulWidget {
  final String classId;
  final String gymId;
  final String className;
  final DateTime occurrenceDate;

  const ClassBatchCheckInDialog({
    super.key,
    required this.classId,
    required this.gymId,
    required this.className,
    required this.occurrenceDate,
  });

  static Future<void> show({
    required BuildContext context,
    required String classId,
    required String gymId,
    required String className,
    required DateTime occurrenceDate,
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
    setState(() => _phase = _Phase.processing);
    context.read<ScheduleBloc>().add(ScheduleBatchCheckInRequested(
          classId: widget.classId,
          occurrenceDate: widget.occurrenceDate,
          memberIds: ids,
        ));
  }

  void _onState(BuildContext context, ScheduleState state) {
    if (_phase != _Phase.processing) return;
    if (state is! ScheduleLoaded || state.isCheckingIn) return;
    if (state.batchCheckInResult != null) {
      setState(() => _phase = _Phase.results);
    } else if (state.checkInError != null) {
      setState(() {
        _phase = _Phase.select;
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
            body: BatchCheckInResultsView(memberNames: _names),
            actions: checkInDoneActions(context),
          ),
        _Phase.select => AppDialog(
            title: 'Update attendees',
            body: BatchCheckInPicker(
              gymId: widget.gymId,
              className: widget.className,
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
