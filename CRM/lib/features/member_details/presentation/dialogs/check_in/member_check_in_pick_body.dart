import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_section.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// The check-in dialog's selection body: the emphasized "Today" (Active) list
/// first, then the secondary "Last 7 days" (Past) list (shown only when it has
/// occurrences). Owns its own gym-scoped occurrence reads via the
/// [ScheduleRepository] — Active = today, Past = the prior 7 days, both with
/// cancelled days filtered out.
class MemberCheckInPickBody extends StatefulWidget {
  final String gymId;
  final String? selectedKey;
  final ValueChanged<EffectiveClassInstance> onSelect;

  const MemberCheckInPickBody({
    super.key,
    required this.gymId,
    required this.onSelect,
    this.selectedKey,
  });

  @override
  State<MemberCheckInPickBody> createState() =>
      _MemberCheckInPickBodyState();
}

class _MemberCheckInPickBodyState extends State<MemberCheckInPickBody> {
  List<EffectiveClassInstance> _active = [];
  List<EffectiveClassInstance> _past = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<ScheduleRepository>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      final results = await Future.wait([
        repo.listEffectiveInstances(widget.gymId, today, today),
        repo.listEffectiveInstances(
          widget.gymId,
          today.subtract(const Duration(days: 7)),
          today.subtract(const Duration(days: 1)),
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _active = results[0].where((i) => !i.isCancelled).toList();
        _past = results[1].where((i) => !i.isCancelled).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'We couldn’t load the class schedule. Please retry.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: DesignConstants.dialogProcessingHeight,
        child: Center(child: AppSpinner()),
      );
    }
    if (_loadError != null) return ErrorMessage(message: _loadError!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        CheckInSection(
          title: 'Today',
          instances: _active,
          selectedClassDateKey: widget.selectedKey,
          onSelect: widget.onSelect,
          emptyLabel: 'No classes scheduled today.',
        ),
        if (_past.isNotEmpty)
          CheckInSection(
            title: 'Last 7 days',
            instances: _past,
            selectedClassDateKey: widget.selectedKey,
            onSelect: widget.onSelect,
          ),
      ],
    );
  }
}
