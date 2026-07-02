import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/class_range_exception.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

final DateFormat _rangeDateLabel = DateFormat('MMM d, yyyy');

/// One row of the class form's "Cancelled ranges" list — "start – end" plus
/// Edit/Remove, or a small spinner in their place while [isPending] (this
/// row's own mutation is in flight).
class ClassCancelledRangeRow extends StatelessWidget {
  final ClassRangeException range;
  final bool isPending;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const ClassCancelledRangeRow({
    super.key,
    required this.range,
    required this.isPending,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            '${_rangeDateLabel.format(range.startDate)} – '
            '${_rangeDateLabel.format(range.endDate)}',
            style: DesignConstants.p,
          ),
        ),
        if (isPending)
          const AppSpinner(size: DesignConstants.iconSizeMedium)
        else ...[
          AppOutlineButton(
            text: 'Edit',
            onPressed: onEdit,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingLarge,
              vertical: DesignConstants.spacingSmall,
            ),
          ),
          AppOutlineButton(
            text: 'Remove',
            onPressed: onRemove,
            borderColor: DesignConstants.badRed,
            textColor: DesignConstants.badRed,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingLarge,
              vertical: DesignConstants.spacingSmall,
            ),
          ),
        ],
      ],
    );
  }
}
