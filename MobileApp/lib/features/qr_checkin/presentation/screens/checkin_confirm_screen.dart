import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/qr_checkin/data/checkin_confirm_args.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/confirm/checkin_confirm_body.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

// How long the confirmation holds before auto-dismissing back to home. Sized
// to let the count-up (1.4s) finish and land, then a brief beat — the member
// is walking into class, so it doesn't linger. Layout/timing math (_k
// carve-out), not a fungible design token.
const Duration _kAutoDismissDelay = Duration(milliseconds: 3600);

/// Step 3 of the QR check-in flow: a quick, auto-dismissing streak count-up
/// confirming the check-in.
///
/// STUB SUCCESS — there is NO member check-in endpoint yet, so nothing is
/// written and the numbers shown are the member's CURRENT streak plus the
/// class's own points value. This is the seam kiosk Phase G plugs into: its
/// backend check-in response (the awarded streak + points_awarded) will feed
/// these same fields once the nonce contract lands, replacing the stub values.
class CheckinConfirmScreen extends StatefulWidget {
  const CheckinConfirmScreen({super.key});

  @override
  State<CheckinConfirmScreen> createState() => _CheckinConfirmScreenState();
}

class _CheckinConfirmScreenState extends State<CheckinConfirmScreen> {
  Timer? _timer;
  bool _dismissed = false;

  /// The current streak, captured once at mount so the count-up target is
  /// stable for the animation (read from the shared profile source).
  late final int _streakWeeks = context
          .read<MemberProfileBloc>()
          .state
          .profile
          ?.retention
          .classStreakWeeks ??
      0;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_kAutoDismissDelay, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted || _dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final confirmArgs = args is CheckinConfirmArgs
        ? args
        : const CheckinConfirmArgs(className: '', pointsWorth: 0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: AppScreenScaffold(
        child: CheckinConfirmBody(
          className: confirmArgs.className,
          pointsWorth: confirmArgs.pointsWorth,
          streakWeeks: _streakWeeks,
          onDone: _dismiss,
        ),
      ),
    );
  }
}
