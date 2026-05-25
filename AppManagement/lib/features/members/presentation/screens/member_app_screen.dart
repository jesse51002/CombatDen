import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/loyalty_tab.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_tab.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/videos_tab.dart';
import 'package:app_management/shared/widgets/app_shell.dart';
import 'package:app_management/shared/widgets/view_switcher.dart';

/// Admin-side configurator for the member-facing CombatDen app, split
/// into three tabs: Theme, Videos, and the Loyalty Program.
class MemberAppScreen extends StatefulWidget {
  const MemberAppScreen({super.key});

  @override
  State<MemberAppScreen> createState() => _MemberAppScreenState();
}

class _MemberAppScreenState extends State<MemberAppScreen> {
  int _tabIndex = 0;

  static const List<String> _labels = ['Theme', 'Videos', 'Loyalty'];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.memberAppPreview,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            ViewSwitcher(
              labels: _labels,
              selectedIndex: _tabIndex,
              onSelected: (i) => setState(() => _tabIndex = i),
            ),
            switch (_tabIndex) {
              1 => const VideosTab(),
              2 => const LoyaltyTab(),
              _ => const ThemeTab(),
            },
          ],
        ),
      ),
    );
  }
}
