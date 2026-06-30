import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';

/// Terminal outcome of a member check-in. The dialog footer drives the next
/// action (Done / Try again); this view only states what happened. Staff always
/// records, so a recorded check-in (✓ "+N points") names the class and shows
/// any gate warnings as a non-blocking note; an idempotent repeat and an
/// unexpected error are the other two outcomes.
class MemberCheckInResultView extends StatelessWidget {
  final String instanceName;
  final CheckInResponse? result;
  final String? error;

  const MemberCheckInResultView({
    super.key,
    required this.instanceName,
    this.result,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _Outcome(
        icon: Symbols.error_sharp,
        color: DesignConstants.badRed,
        title: 'Couldn’t check in',
        detail: error!,
      );
    }
    final r = result;
    if (r == null) return const SizedBox.shrink();
    if (r.alreadyCheckedIn) {
      return _Outcome(
        icon: Symbols.check_circle_sharp,
        color: DesignConstants.goodGreen,
        title: 'Already checked into $instanceName',
        detail: 'No change — attendance was already recorded.',
      );
    }
    return _Outcome(
      icon: Symbols.check_circle_sharp,
      color: DesignConstants.goodGreen,
      title: 'Checked into $instanceName',
      detail: '+${r.pointsAwarded} points awarded.',
      note: r.hasWarnings ? CheckInWarning.summarize(r.warnings) : null,
    );
  }
}

class _Outcome extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  /// A non-blocking heads-up (the recorded check-in's gate warnings), shown
  /// under the detail in the secondary tone.
  final String? note;

  const _Outcome({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          icon,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeBig,
          color: color,
        ),
        Column(
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: DesignConstants.h3.copyWith(color: color),
            ),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            if (note != null)
              Text(
                note!,
                textAlign: TextAlign.center,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.okYellow,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
