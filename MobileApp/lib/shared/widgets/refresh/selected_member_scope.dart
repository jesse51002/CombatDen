import 'package:flutter/widgets.dart';

import 'package:mobile_app/core/state/selected_member.dart';

/// Rebuilds [builder] whenever the selected member's fields change.
///
/// Each tab root wraps itself in this so a pull that lands new CAPABILITY
/// FLAGS re-composes the page that is actually on screen. The shell also
/// listens to [selectedMember], but it re-keys its subtree on the member id
/// alone — an id that a refresh never changes — and the routes already pushed
/// onto its nested navigator do not rebuild with it. Without this scope a gym
/// toggling its rank ladder, rewards or videos would update the stored flags
/// and change nothing visible until the tab was re-entered.
///
/// What it re-derives: `gymNavTabs()` (which bottom-nav tabs exist), the
/// profile page's rank-vs-rank-less shape, and the gym name / logo the topbars
/// read straight off [selectedMember].
class SelectedMemberScope extends StatelessWidget {
  const SelectedMemberScope({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedMember,
      builder: (context, _) => builder(context),
    );
  }
}
