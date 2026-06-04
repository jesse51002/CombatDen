import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/mock_employees.dart';

/// The classes this employee leads. Coaches run many weekly sessions, so the
/// list is paged — a handful at a time with prev/next controls — instead of
/// scrolling the profile forever. The "go deeper" link between an employee and
/// what they actually run on the mat.
class EmployeeClassesSection extends StatefulWidget {
  final List<TaughtClass> classes;

  const EmployeeClassesSection({super.key, required this.classes});

  @override
  State<EmployeeClassesSection> createState() => _EmployeeClassesSectionState();
}

class _EmployeeClassesSectionState extends State<EmployeeClassesSection> {
  static const int _pageSize = 6;
  int _page = 0;

  int get _pageCount => (widget.classes.length / _pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    final total = widget.classes.length;
    final start = _page * _pageSize;
    final end = math.min(start + _pageSize, total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final taught in widget.classes.sublist(start, end))
          _ClassRow(taught: taught),
        if (_pageCount > 1)
          _Pager(
            start: start,
            end: end,
            total: total,
            onPrev: _page > 0 ? () => setState(() => _page--) : null,
            onNext: _page < _pageCount - 1 ? () => setState(() => _page++) : null,
          ),
      ],
    );
  }
}

class _ClassRow extends StatelessWidget {
  final TaughtClass taught;
  const _ClassRow({required this.taught});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          Symbols.event_sharp,
          size: DesignConstants.iconSizeMedium,
          color: DesignConstants.text2nd,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(taught.name, style: DesignConstants.h3),
              Text(
                taught.schedule,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pager extends StatelessWidget {
  final int start;
  final int end;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _Pager({
    required this.start,
    required this.end,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Showing ${start + 1}–$end of $total',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            _PagerButton(icon: Symbols.chevron_left_sharp, onTap: onPrev),
            _PagerButton(icon: Symbols.chevron_right_sharp, onTap: onNext),
          ],
        ),
      ],
    );
  }
}

class _PagerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PagerButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingSmall),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Icon(
          icon,
          size: DesignConstants.iconSizeMedium,
          color: enabled ? DesignConstants.text : DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}
