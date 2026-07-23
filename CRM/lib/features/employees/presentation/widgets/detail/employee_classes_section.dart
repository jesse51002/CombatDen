import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/models/employee_taught_class.dart';

/// The classes this employee leads — one row per class with its cadence and
/// weekly session slots. The "go deeper" link between an employee and what they
/// actually run on the mat.
class EmployeeClassesSection extends StatelessWidget {
  final List<EmployeeTaughtClass> classes;

  const EmployeeClassesSection({super.key, required this.classes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [for (final taught in classes) _ClassRow(taught: taught)],
    );
  }
}

class _ClassRow extends StatelessWidget {
  final EmployeeTaughtClass taught;

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
              Text(taught.className, style: DesignConstants.h3),
              Text(
                taught.cadenceLabel,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              for (final slot in taught.slotLabels)
                Text(
                  slot,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
