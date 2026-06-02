import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/live_theme_preview_tab.dart';
import 'package:app_management/features/theme_browser/presentation/widgets/theme_browser_top_bar.dart';

/// Full-screen host for the reusable [LiveThemePreviewTab] module — the public,
/// separately-deployed theme browser.
///
/// No admin nav rail: just the top bar and the browser filling the rest. The
/// padding mirrors what the admin preview applies (see `member_app_screen.dart`)
/// so the browser sits identically in both hosts. `routePath: AppRoutes.home`
/// keeps deep links rooted at the themes site (`/#/?theme=…`) rather than the
/// admin's `/members/app-preview`.
class ThemeBrowserPage extends StatelessWidget {
  const ThemeBrowserPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ThemeBrowserTopBar(),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(DesignConstants.paddingBig),
              child: LiveThemePreviewTab(routePath: AppRoutes.home),
            ),
          ),
        ],
      ),
    );
  }
}
