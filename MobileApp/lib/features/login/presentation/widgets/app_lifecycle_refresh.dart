import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/stats/data/celebration_detector.dart';

/// Fires a silent [MemberProfileRefreshRequested] whenever the app returns to
/// the foreground (per the live-session rules: no polling), and runs the
/// app-open celebration check on the same hook — once after the member's home
/// mounts (app open / member switch) and again on every foreground.
///
/// The check is **armed** by that hook and **consumed** by the first loaded
/// profile that arrives while armed, because the promotion half of the
/// decision rides the profile and the profile is not loaded yet at the
/// post-frame callback. Arming rather than checking on every `loaded` is what
/// stops a mid-session pull-to-refresh taking over the screen while the member
/// is mid-booking: the house law is that an entrance plays once per mount and
/// never re-fires on a silent refresh, and here it is enforced at the push.
/// The watermarks are the backstop, not the mechanism — even if the listener
/// ran twice, both decision rules would answer "skip".
///
/// One benign consequence: if a foreground's refresh returns a byte-identical
/// profile, `Equatable` suppresses the emission and the arm is never consumed.
/// That is correct (an identical profile carries no new promotion) and the arm
/// simply clears on the next real emission.
///
/// Lives BELOW the [MemberProfileBloc] provider so it can read it, and BELOW
/// [navigatorKey]'s [Navigator] so the celebration flow pushes onto the shell
/// navigator. Recreated with the shell's keyed subtree on a member switch, so
/// it always drives — and re-checks — the current member.
class AppLifecycleRefresh extends StatefulWidget {
  const AppLifecycleRefresh({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The shell navigator the celebration flow is pushed onto.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppLifecycleRefresh> createState() => _AppLifecycleRefreshState();
}

class _AppLifecycleRefreshState extends State<AppLifecycleRefresh>
    with WidgetsBindingObserver {
  final CelebrationDetector _celebration = CelebrationDetector();

  /// True between an app open / foreground and the loaded profile that spends
  /// it. Exactly one celebration check per arming.
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Once after this member's home mounts — covers the initial app open and a
    // member switch (this widget is recreated with the keyed subtree).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _armed = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onProfile(BuildContext context, MemberProfileState state) {
    if (!_armed) return;
    if (state.status != MemberProfileStatus.loaded || state.profile == null) {
      return;
    }
    _armed = false;
    _celebration.maybeFire(widget.navigatorKey.currentState, state.profile);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context
          .read<MemberProfileBloc>()
          .add(const MemberProfileRefreshRequested());
      _armed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberProfileBloc, MemberProfileState>(
      listener: _onProfile,
      child: widget.child,
    );
  }
}
