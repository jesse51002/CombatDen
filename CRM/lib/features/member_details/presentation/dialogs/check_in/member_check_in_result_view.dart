import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/check_in/data/models/signup_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_reserve_selection.dart';

/// Terminal outcome of the member check-in/reserve dialog, branched on
/// [action]:
///
/// - **Check in**: a recorded check-in (✓ "+N points", any gate warnings as
///   a non-blocking note), an idempotent repeat, a hold for confirmation
///   (the gate warned and nothing was written — offer "Check in anyway"),
///   or an unexpected error. Driven by [checkInResult].
/// - **Reserve**: a new reservation ("Reserved for …"), an idempotent
///   repeat ("Already reserved"), or an error (e.g. "Class is full").
///   Driven by [reserveResult]. There is no "confirm anyway" override here
///   — a reservation either succeeds or the room is full — mirroring the
///   schedule feature's own sign-up dialog.
///
/// The dialog footer drives the next action (Done / Check in anyway / Try
/// again); this view only states what happened.
class MemberCheckInResultView extends StatelessWidget {
  final CheckInReserveAction action;
  final String instanceName;
  final CheckInResponse? checkInResult;
  final SignupResponse? reserveResult;
  final String? error;

  const MemberCheckInResultView({
    super.key,
    required this.action,
    required this.instanceName,
    this.checkInResult,
    this.reserveResult,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (action == CheckInReserveAction.reserve) {
      return _buildReserve();
    }
    return _buildCheckIn();
  }

  Widget _buildReserve() {
    if (error != null) {
      return _Outcome(
        icon: Symbols.error_sharp,
        color: DesignConstants.badRed,
        title: 'Couldn’t reserve a spot',
        detail: error!,
      );
    }
    final r = reserveResult;
    if (r == null) return const SizedBox.shrink();
    if (r.alreadySignedUp) {
      return _Outcome(
        icon: Symbols.check_circle_sharp,
        color: DesignConstants.goodGreen,
        title: 'Already reserved for $instanceName',
        detail: 'No change — a spot was already held.',
      );
    }
    return _Outcome(
      icon: Symbols.check_circle_sharp,
      color: DesignConstants.goodGreen,
      title: 'Reserved for $instanceName',
      detail: 'A spot is held for this occurrence.',
    );
  }

  Widget _buildCheckIn() {
    if (error != null) {
      return _Outcome(
        icon: Symbols.error_sharp,
        color: DesignConstants.badRed,
        title: 'Couldn’t check in',
        detail: error!,
      );
    }
    final r = checkInResult;
    if (r == null) return const SizedBox.shrink();
    if (r.requiresConfirmation) {
      return _Outcome(
        icon: Symbols.warning_sharp,
        color: DesignConstants.okYellow,
        title: 'Not checked in to $instanceName',
        detail: '${CheckInWarning.summarize(r.warnings)}. Use "Check in '
            'anyway" to override the gate (front-desk coverage).',
      );
    }
    // The member's post-check-in weekly streak, appended to a recorded/repeat
    // outcome when they have one.
    final streakSuffix = r.classStreakWeeks > 0
        ? ' · ${r.classStreakWeeks}-week streak'
        : '';
    if (r.alreadyCheckedIn) {
      return _Outcome(
        icon: Symbols.check_circle_sharp,
        color: DesignConstants.goodGreen,
        title: 'Already checked into $instanceName',
        detail: 'No change — attendance was already recorded$streakSuffix.',
      );
    }
    return _Outcome(
      icon: Symbols.check_circle_sharp,
      color: DesignConstants.goodGreen,
      title: 'Checked into $instanceName',
      detail: '+${r.pointsAwarded} points awarded$streakSuffix.',
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
