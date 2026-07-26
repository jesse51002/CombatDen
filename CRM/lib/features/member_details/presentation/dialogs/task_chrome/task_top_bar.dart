import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The context bar a nested staff dialog wears in place of the dialog's own
/// title row — the same band the run behind it carries, so a task opened over
/// the wizard reads as part of the same surface rather than as a stray popup.
///
/// It answers the two things the centred head deliberately does not: WHAT this
/// dialog is, and WHOSE record it was opened against. The head below states
/// the step, so neither is ever a second copy of the other.
///
/// [onClose] is null exactly while leaving would strand a commit whose outcome
/// nobody has read yet; the X then renders disabled rather than vanishing, so
/// nothing moves under the cursor mid-task.
class TaskTopBar extends StatelessWidget {
  /// What this dialog is — the task, not the step.
  final String what;

  /// The record it was opened against. Empty or null drops the clause rather
  /// than printing a trailing separator.
  final String? who;

  final VoidCallback? onClose;

  /// What closing this dialog gives up, for the screen reader.
  final String closeTooltip;

  const TaskTopBar({
    super.key,
    required this.what,
    required this.closeTooltip,
    this.who,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final record = who?.trim() ?? '';
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(what, style: DesignConstants.h3),
        Expanded(
          child: record.isEmpty
              ? const SizedBox.shrink()
              : Text(
                  '· $record',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        IconButton(
          onPressed: onClose,
          icon: Icon(
            Symbols.close_sharp,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
          tooltip: closeTooltip,
        ),
      ],
    );
  }
}
