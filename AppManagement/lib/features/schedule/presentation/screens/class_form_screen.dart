import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/features/schedule/presentation/widgets/form/class_days_section.dart';
import 'package:app_management/features/schedule/presentation/widgets/form/class_details_section.dart';
import 'package:app_management/features/schedule/presentation/widgets/form/class_form_actions.dart';
import 'package:app_management/features/schedule/presentation/widgets/form/class_rewards_section.dart';
import 'package:app_management/features/schedule/presentation/widgets/form/class_schedule_section.dart';
import 'package:app_management/shared/widgets/app_shell.dart';

/// Full-page Add/Edit Class form. Visual-only: Save is a no-op that pops.
/// Pass [existing] to prefill the fields for editing.
class ClassFormScreen extends StatefulWidget {
  final ScheduleClass? existing;

  const ClassFormScreen({super.key, this.existing});

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pointsController = TextEditingController(text: '50');
  final _capacityController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final _intervalController = TextEditingController(text: '1');

  TimeOfDay? _classTime;
  RecurringUnit _recurringUnit = RecurringUnit.weekly;
  DateTime? _startDate;
  DateTime? _endDate;
  Set<int> _selectedDays = {};
  Map<int, String?> _instructorByDay = {};
  String? _imageUrl;
  String? _imageAsset;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c == null) return;
    _nameController.text = c.className;
    _descriptionController.text = c.description ?? '';
    _pointsController.text = c.pointsWorth.toString();
    _capacityController.text = c.maxCapacity?.toString() ?? '';
    _durationController.text = c.durationMinutes.toString();
    _intervalController.text = c.recurringInterval.toString();
    _classTime = c.classTime;
    _recurringUnit = c.recurringUnit;
    _startDate = c.startDate;
    _endDate = c.endDate;
    _selectedDays = {...c.activeDays};
    _instructorByDay = {...c.instructorIdByDay};
    _imageUrl = c.imageUrl;
    _imageAsset = c.imageAsset;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _pointsController.dispose();
    _capacityController.dispose();
    _durationController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
        _instructorByDay.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  void _close() => Navigator.pop(context);

  void _save() {
    debugPrint('TODO: save class "${_nameController.text}"');
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AppShell(
      activeRoute: AppRoutes.schedule,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            _FormHeader(
              title: isEdit ? 'Edit Class' : 'Add New Class',
              onBack: _close,
            ),
            ClassDetailsSection(
              nameController: _nameController,
              descriptionController: _descriptionController,
              imageUrl: _imageUrl,
              imageAsset: _imageAsset,
            ),
            ClassRewardsSection(
              pointsController: _pointsController,
              capacityController: _capacityController,
            ),
            ClassScheduleSection(
              classTime: _classTime,
              onTimeChanged: (t) => setState(() => _classTime = t),
              durationController: _durationController,
              recurringUnit: _recurringUnit,
              onUnitChanged: (u) =>
                  setState(() => _recurringUnit = u ?? _recurringUnit),
              intervalController: _intervalController,
              startDate: _startDate,
              onStartChanged: (d) => setState(() => _startDate = d),
              endDate: _endDate,
              onEndChanged: (d) => setState(() => _endDate = d),
            ),
            ClassDaysSection(
              selectedDays: _selectedDays,
              onToggleDay: _toggleDay,
              instructorByDay: _instructorByDay,
              onInstructorChanged: (day, id) =>
                  setState(() => _instructorByDay[day] = id),
            ),
            ClassFormActions(onCancel: _close, onSave: _save),
          ],
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _FormHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.all(DesignConstants.spacingSmall),
            child: Icon(
              Symbols.arrow_back_sharp,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ),
        Text(
          title,
          style: DesignConstants.h1.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
