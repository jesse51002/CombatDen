import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/form/app_date_field.dart';

/// Fixed-height spinner body shared by the schedule cancel dialogs while the
/// exception write + board reload run.
class ScheduleCancelProcessing extends StatelessWidget {
  const ScheduleCancelProcessing({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: DesignConstants.dialogProcessingHeight,
      child: Center(child: AppSpinner()),
    );
  }
}

/// Terminal success body shared by the schedule cancel dialogs: a green check
/// over a [message] the user dismisses. The board has already reloaded by the
/// time this shows, so dismissing drops the user onto a fresh schedule.
class ScheduleCancelSuccess extends StatelessWidget {
  final String message;

  const ScheduleCancelSuccess({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.goodGreen,
        ),
        Text(
          message,
          textAlign: TextAlign.center,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}

/// Pick body for cancelling a date range: an explanation plus the inclusive
/// start/end date fields and the inline error after a failed attempt. The
/// dialog owns the selected [start] / [end] and the validation.
class ClassRangeCancelPick extends StatelessWidget {
  final String className;
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime> onStart;
  final ValueChanged<DateTime> onEnd;
  final String? inlineError;

  const ClassRangeCancelPick({
    super.key,
    required this.className,
    required this.start,
    required this.end,
    required this.onStart,
    required this.onEnd,
    this.inlineError,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'Cancel every $className from the start through the end date '
          '(inclusive). Other dates are not affected.',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        AppDateField(label: 'Start date', value: start, onChanged: onStart),
        AppDateField(label: 'End date', value: end, onChanged: onEnd),
        if (inlineError != null) ErrorMessage(message: inlineError!),
      ],
    );
  }
}
