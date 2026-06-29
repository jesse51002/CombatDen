import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';

/// Terminal outcome of a member check-in. The dialog footer drives the next
/// action (Done / Check in anyway / Try again); this view only states what
/// happened: a recorded check-in (✓ "+N points"), an idempotent repeat, a skip
/// with its reason, or an unexpected error.
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
    if (r.isSkipped) {
      return _Outcome(
        icon: Symbols.do_not_disturb_on_sharp,
        color: DesignConstants.text2nd,
        title: 'Not checked in to $instanceName',
        detail: '${r.skipReason!.displayLabel}. Use “Check in anyway” to '
            'override the gate (front-desk coverage).',
      );
    }
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
    );
  }
}

class _Outcome extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  const _Outcome({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
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
          ],
        ),
      ],
    );
  }
}
