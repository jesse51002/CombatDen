import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';

/// Fires a silent [MemberProfileRefreshRequested] whenever the app returns to
/// the foreground — the single foreground hook the post-class celebration
/// check will later share (per the live-session rules: no polling). Lives
/// BELOW the [MemberProfileBloc] provider so it can read it; recreated with the
/// shell's keyed subtree on a member switch, so it always drives the current
/// member's bloc.
class AppLifecycleRefresh extends StatefulWidget {
  const AppLifecycleRefresh({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleRefresh> createState() => _AppLifecycleRefreshState();
}

class _AppLifecycleRefreshState extends State<AppLifecycleRefresh>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context
          .read<MemberProfileBloc>()
          .add(const MemberProfileRefreshRequested());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
