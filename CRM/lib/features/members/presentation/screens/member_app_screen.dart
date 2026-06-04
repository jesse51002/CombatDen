import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/url_sync.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/loyalty_tab.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/live_theme_preview_tab.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/videos_tab.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// The three tabs of the member-app configurator. The enum order matches the
/// [ViewSwitcher] labels and the `switch (_tabIndex)` below, and each maps to a
/// deep-linkable route so the open tab shows in the URL and restores on refresh.
enum MemberAppTab { theme, videos, loyalty }

/// The route that addresses [tab] (the base path is the Theme tab).
String _routeForTab(MemberAppTab tab) => switch (tab) {
  MemberAppTab.theme => AppRoutes.memberAppPreview,
  MemberAppTab.videos => AppRoutes.memberAppPreviewVideos,
  MemberAppTab.loyalty => AppRoutes.memberAppPreviewLoyalty,
};

/// Admin-side configurator for the member-facing CombatDen app, split
/// into three tabs: Theme, Videos, and the Loyalty Program.
class MemberAppScreen extends StatefulWidget {
  /// The tab to open on mount — set per route so `/members/app-preview/videos`
  /// and `…/loyalty` deep-link to their tab.
  final MemberAppTab initialTab;

  const MemberAppScreen({super.key, this.initialTab = MemberAppTab.theme});

  @override
  State<MemberAppScreen> createState() => _MemberAppScreenState();
}

class _MemberAppScreenState extends State<MemberAppScreen> {
  late int _tabIndex = widget.initialTab.index;

  static const List<String> _labels = ['Theme', 'Videos', 'Loyalty'];

  // Switching tabs is a local `setState` (no route push) so the Theme tab's
  // ThemeRuntime catalog isn't torn down and re-fetched on every tab tap. The
  // nested navigator's observer can't see a `setState`, so reflect the open tab
  // into the URL here instead.
  void _onTabSelected(int index) {
    setState(() => _tabIndex = index);
    syncBrowserUrl(_routeForTab(MemberAppTab.values[index]));
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      // Every tab keeps the "Member App" rail item highlighted — the section is
      // the same regardless of which tab is open.
      activeRoute: AppRoutes.memberAppPreview,
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            ViewSwitcher(
              labels: _labels,
              selectedIndex: _tabIndex,
              onSelected: _onTabSelected,
            ),
            // The Theme tab is a full-height layout (the phone fills the
            // space, the theme list scrolls on its own). The other tabs keep
            // their own scroll.
            Expanded(
              child: switch (_tabIndex) {
                1 => const SingleChildScrollView(child: VideosTab()),
                2 => const SingleChildScrollView(child: LoyaltyTab()),
                _ => const LiveThemePreviewTab(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
