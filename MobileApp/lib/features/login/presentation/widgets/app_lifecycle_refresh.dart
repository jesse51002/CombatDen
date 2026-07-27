import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/stats/data/celebration_detector.dart';

/// Fires a silent [MemberProfileRefreshRequested] whenever the app returns to
/// the foreground (per the live-session rules: no polling), and runs the
/// post-class celebration check on the same hook — once after the member's
/// home mounts (app open / member switch) and again on every foreground.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Once after this member's home mounts — covers the initial app open and a
    // member switch (this widget is recreated with the keyed subtree).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCelebration());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _checkCelebration() {
    if (!mounted) return;
    _celebration.maybeFire(widget.navigatorKey.currentState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context
          .read<MemberProfileBloc>()
          .add(const MemberProfileRefreshRequested());
      _checkCelebration();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
