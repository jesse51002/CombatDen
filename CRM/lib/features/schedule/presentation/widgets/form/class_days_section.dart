import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_slot_row.dart';
import 'package:crm/features/schedule/presentation/widgets/form/slot_draft.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/form/day_of_week_selector.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

const List<String> _dayNames = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday',
  'Thursday', 'Friday', 'Saturday',
];

/// Sentinel day-index key for a daily/monthly schedule's single reserved
/// `"all"` slot list — distinct from the 0-6 weekday indices so the two
/// buckets never collide, and switching [RecurringUnit] between weekly and
/// daily/monthly never silently loses the other mode's already-entered
/// slots (both can coexist in the form's map; only the relevant one renders
/// and gets submitted).
const int kAllDaysSlotKey = -1;

/// "Days & times" (weekly) / "Times" (daily, monthly) form section.
///
/// For a **weekly** class: [DayOfWeekSelector] chips pick the active
/// weekdays; each active day then shows its own column of (time, instructor)
/// slot rows plus an "Add time" button — several times per day are allowed.
/// For a **daily/monthly** class: the day chips are hidden and a single
/// "Times" column edits the reserved [kAllDaysSlotKey] bucket instead.
///
/// [daySlots] is the full draft map (both weekday buckets AND the "all"
/// bucket may be populated at once — see [kAllDaysSlotKey]); this widget only
/// renders whichever half [recurringUnit] calls for.
class ClassDaysSection extends StatelessWidget {
  final RecurringUnit recurringUnit;
  final Map<int, List<SlotDraft>> daySlots;
  final ValueChanged<int> onToggleDay;
  final void Function(int day) onAddSlot;
  final void Function(int day, int index) onRemoveSlot;
  final void Function(int day, int index, TimeOfDay time) onSlotTimeChanged;
  final void Function(int day, int index, String? instructorId)
      onSlotInstructorChanged;
  final List<InstructorOption> instructors;

  const ClassDaysSection({
    super.key,
    required this.recurringUnit,
    required this.daySlots,
    required this.onToggleDay,
    required this.onAddSlot,
    required this.onRemoveSlot,
    required this.onSlotTimeChanged,
    required this.onSlotInstructorChanged,
    required this.instructors,
  });

  bool get _isWeekly => recurringUnit == RecurringUnit.weekly;

  Set<int> get _selectedDays =>
      daySlots.keys.where((k) => k >= 0 && k <= 6).toSet();

  @override
  Widget build(BuildContext context) {
    final activeDays = _selectedDays.toList()..sort();
    return SubtitleSection(
      title: _isWeekly ? 'Days & times' : 'Times',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (_isWeekly)
            DayOfWeekSelector(
              selectedDays: _selectedDays,
              onToggle: onToggleDay,
            ),
          if (instructors.isEmpty)
            Text(
              'No instructors found yet — assign one to a class to build the '
              'roster. You can still save without an instructor.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          if (_isWeekly)
            for (final day in activeDays)
              _DaySlotList(
                title: _dayNames[day],
                slots: daySlots[day] ?? const [],
                instructors: instructors,
                onAdd: () => onAddSlot(day),
                onRemove: (i) => onRemoveSlot(day, i),
                onTimeChanged: (i, t) => onSlotTimeChanged(day, i, t),
                onInstructorChanged: (i, id) =>
                    onSlotInstructorChanged(day, i, id),
              )
          else
            _DaySlotList(
              title: null,
              slots: daySlots[kAllDaysSlotKey] ?? const [],
              instructors: instructors,
              onAdd: () => onAddSlot(kAllDaysSlotKey),
              onRemove: (i) => onRemoveSlot(kAllDaysSlotKey, i),
              onTimeChanged: (i, t) =>
                  onSlotTimeChanged(kAllDaysSlotKey, i, t),
              onInstructorChanged: (i, id) =>
                  onSlotInstructorChanged(kAllDaysSlotKey, i, id),
            ),
        ],
      ),
    );
  }
}

/// One day's (or the "all" bucket's) column of [ClassSlotRow]s + "Add time".
class _DaySlotList extends StatelessWidget {
  final String? title;
  final List<SlotDraft> slots;
  final List<InstructorOption> instructors;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int index, TimeOfDay time) onTimeChanged;
  final void Function(int index, String? instructorId) onInstructorChanged;

  const _DaySlotList({
    required this.title,
    required this.slots,
    required this.instructors,
    required this.onAdd,
    required this.onRemove,
    required this.onTimeChanged,
    required this.onInstructorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final slotColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (slots.isNotEmpty) const ClassSlotHeaderRow(),
        for (var i = 0; i < slots.length; i++)
          ClassSlotRow(
            time: slots[i].time,
            instructorId: slots[i].instructorId,
            instructors: instructors,
            onTimeChanged: (t) => onTimeChanged(i, t),
            onInstructorChanged: (id) => onInstructorChanged(i, id),
            onRemove: () => onRemove(i),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppOutlineButton(
            text: 'Add time',
            onPressed: onAdd,
            icon: Icon(
              Symbols.add_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingLarge,
              vertical: DesignConstants.spacingSmall,
            ),
          ),
        ),
      ],
    );

    // Daily/monthly "Times": the section title already leads this single
    // list, so render it flush with no sub-heading.
    if (title == null) return slotColumn;

    // Weekly: the day name is the group leader; its slots sit indented beneath
    // it so each day reads as one deliberate block.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(title!, style: DesignConstants.h3),
        Padding(
          padding: const EdgeInsets.only(left: DesignConstants.spacingLarge),
          child: slotColumn,
        ),
      ],
    );
  }
}
