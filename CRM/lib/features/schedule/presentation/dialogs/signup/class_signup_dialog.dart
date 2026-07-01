import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/check_in/presentation/widgets/check_in_dialog_actions.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/batch_check_in_picker.dart';
import 'package:crm/features/schedule/presentation/dialogs/signup/signup_results_view.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

enum _Phase { select, processing, results }

/// "Reserve members" for one class occurrence — the FUTURE-side counterpart
/// of `ClassBatchCheckInDialog`: pick members → submit → a per-member results
/// step (✓ reserved / already reserved / ✗ failed, e.g. "Class is full").
/// There is no batch sign-up endpoint — [ScheduleBloc] loops
/// `POST /api/v1/signup` once per member; one member's failure never sinks
/// the rest, and there's no "confirm anyway" retry (unlike check-in's
/// warnings) since a reservation either succeeds or the room is full. Shares
/// the board's [ScheduleBloc] (a successful run reloads the week so the
/// board's "N reserved" chip updates).
class ClassSignupDialog extends StatefulWidget {
  final String classId;
  final String gymId;
  final String className;
  final DateTime occurrenceDate;

  const ClassSignupDialog({
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
        child: ClassSignupDialog(
          classId: classId,
          gymId: gymId,
          className: className,
          occurrenceDate: occurrenceDate,
        ),
      ),
    );
  }

  @override
  State<ClassSignupDialog> createState() => _ClassSignupDialogState();
}

class _ClassSignupDialogState extends State<ClassSignupDialog> {
  _Phase _phase = _Phase.select;
  final Set<String> _selectedIds = {};
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    context.read<ScheduleBloc>().add(const ScheduleSignUpCleared());
  }

  void _toggle(MemberPickerEntry entry) {
    setState(() {
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
    context.read<ScheduleBloc>().add(ScheduleSignUpRequested(
          classId: widget.classId,
          occurrenceDate: widget.occurrenceDate,
          memberIds: ids,
        ));
  }

  void _onState(BuildContext context, ScheduleState state) {
    if (_phase != _Phase.processing) return;
    if (state is! ScheduleLoaded || state.isSigningUp) return;
    if (state.signupResult != null) {
      setState(() => _phase = _Phase.results);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ScheduleBloc, ScheduleState>(
      listener: _onState,
      child: switch (_phase) {
        _Phase.processing => const AppDialog(
            title: 'Reserve members',
            body: CheckInProcessingView(),
          ),
        _Phase.results => AppDialog(
            title: 'Reserve members',
            body: SignupResultsView(memberNames: _names),
            actions: checkInDoneActions(context),
          ),
        _Phase.select => AppDialog(
            title: 'Reserve members',
            body: BatchCheckInPicker(
              gymId: widget.gymId,
              description: 'Pick the members to reserve a spot in this '
                  '${widget.className}.',
              selectedIds: _selectedIds,
              onToggle: _toggle,
            ),
            actions: checkInChoiceActions(
              primaryLabel: _selectedIds.isEmpty
                  ? 'Reserve'
                  : 'Reserve ${_selectedIds.length}',
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
