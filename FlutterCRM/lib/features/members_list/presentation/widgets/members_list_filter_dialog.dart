import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// Result returned by [MembersListFilterDialog].
class FilterDialogResult {
  final List<MembershipStatus> statuses;
  final DateRangeFilter? dateRange;

  const FilterDialogResult({
    required this.statuses,
    this.dateRange,
  });
}

/// A branded filter dialog with two sections:
/// membership status and date range.
class MembersListFilterDialog extends StatefulWidget {
  final MembersListFilters currentFilters;

  const MembersListFilterDialog({
    super.key,
    required this.currentFilters,
  });

  @override
  State<MembersListFilterDialog> createState() =>
      _MembersListFilterDialogState();
}

class _MembersListFilterDialogState
    extends State<MembersListFilterDialog> {
  List<MembershipStatus> _selectedStatuses = [];
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedStatuses = List.of(
      widget.currentFilters.membershipStatus,
    );
    final dr = widget.currentFilters.dateRange;
    if (dr != null) {
      _startDate = dr.startDate != null
          ? DateTime.tryParse(dr.startDate!)
          : null;
      _endDate = dr.endDate != null
          ? DateTime.tryParse(dr.endDate!)
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DesignConstants.popup,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      contentPadding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Membership Status'),
            const SizedBox(
              height: DesignConstants.spacingMedium,
            ),
            _statusRow([
              MembershipStatus.active,
              MembershipStatus.frozen,
              MembershipStatus.cancelled,
            ]),
            const SizedBox(
              height: DesignConstants.spacingMedium,
            ),
            _statusRow([
              MembershipStatus.trial,
              MembershipStatus.ended,
              MembershipStatus.overdue,
            ]),
            const SizedBox(
              height: DesignConstants.spacingMedium,
            ),
            _statusRow([
              MembershipStatus.noMembership,
            ]),
            const SizedBox(
              height: DesignConstants.spacingLarge,
            ),
            _sectionLabel('Start Date'),
            const SizedBox(
              height: DesignConstants.spacingMedium,
            ),
            _dateRangeSelector(),
            const SizedBox(
              height: DesignConstants.spacingBig,
            ),
            _actionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: DesignConstants.h3.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }

  Widget _statusRow(List<MembershipStatus> statuses) {
    return Wrap(
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingMedium,
      children: statuses.map((status) {
        final selected =
            _selectedStatuses.contains(status);
        return _toggleChip(
          label: status.displayLabel,
          selected: selected,
          onTap: () => _toggleStatus(status),
        );
      }).toList(),
    );
  }

  Widget _toggleChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor10
              : null,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.text,
            width: DesignConstants.buttonBorderSize,
          ),
        ),
        child: Text(
          label,
          style: DesignConstants.p.copyWith(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }

  Widget _dateRangeSelector() {
    final formatter = DateFormat('MMM d, yyyy');

    return Row(
      children: [
        Expanded(
          child: _dateButton(
            label: _startDate != null
                ? formatter.format(_startDate!)
                : 'Start date',
            hasValue: _startDate != null,
            onTap: () => _pickDate(isStart: true),
          ),
        ),
        const SizedBox(
          width: DesignConstants.spacingMedium,
        ),
        Expanded(
          child: _dateButton(
            label: _endDate != null
                ? formatter.format(_endDate!)
                : 'End date',
            hasValue: _endDate != null,
            onTap: () => _pickDate(isStart: false),
          ),
        ),
        if (_startDate != null ||
            _endDate != null) ...[
          const SizedBox(
            width: DesignConstants.spacingSmall,
          ),
          GestureDetector(
            onTap: () => setState(() {
              _startDate = null;
              _endDate = null;
            }),
            child: Icon(
              Symbols.close_sharp,
              size: 14,
              color: DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateButton({
    required String label,
    required bool hasValue,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          border: Border.all(
            color: hasValue
                ? DesignConstants.primaryColor
                : DesignConstants.text,
            width: DesignConstants.buttonBorderSize,
          ),
          color: hasValue
              ? DesignConstants.primaryColor10
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Symbols.calendar_today_sharp,
              size: 16,
              color: hasValue
                  ? DesignConstants.primaryColor
                  : DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
            const SizedBox(
              width: DesignConstants.spacingMedium,
            ),
            Expanded(
              child: Text(
                label,
                style: DesignConstants.p.copyWith(
                  color: hasValue
                      ? DesignConstants.primaryColor
                      : DesignConstants.text3rd,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({
    required bool isStart,
  }) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: DesignConstants.primaryColor,
              onPrimary: DesignConstants.text,
              surface: DesignConstants.popup,
              onSurface: DesignConstants.text,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor:
                  DesignConstants.popup,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      // Auto-swap if end is before start
      if (_startDate != null &&
          _endDate != null &&
          _endDate!.isBefore(_startDate!)) {
        final temp = _startDate;
        _startDate = _endDate;
        _endDate = temp;
      }
    });
  }

  Widget _actionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _clearAll,
          child: Text(
            'Clear All',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text3rd,
            ),
          ),
        ),
        const SizedBox(
          width: DesignConstants.spacingMedium,
        ),
        TextButton(
          onPressed: _apply,
          child: Text(
            'Apply',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
    );
  }

  void _toggleStatus(MembershipStatus status) {
    setState(() {
      if (_selectedStatuses.contains(status)) {
        _selectedStatuses.remove(status);
      } else {
        _selectedStatuses.add(status);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedStatuses.clear();
      _startDate = null;
      _endDate = null;
    });
  }

  void _apply() {
    DateRangeFilter? dateRange;
    if (_startDate != null || _endDate != null) {
      final formatter = DateFormat('yyyy-MM-dd');
      dateRange = DateRangeFilter(
        startDate: _startDate != null
            ? formatter.format(_startDate!)
            : null,
        endDate: _endDate != null
            ? formatter.format(_endDate!)
            : null,
      );
    }

    Navigator.of(context).pop(
      FilterDialogResult(
        statuses: List.of(_selectedStatuses),
        dateRange: dateRange,
      ),
    );
  }
}
