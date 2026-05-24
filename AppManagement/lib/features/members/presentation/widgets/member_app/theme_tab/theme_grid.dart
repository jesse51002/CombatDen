import 'package:flutter/material.dart';

import 'package:app_management/features/members/data/mock_app_themes.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_card.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "App Theme" section: a reflowing grid of every theme preset, the
/// active one highlighted. Wider than the member app's vertical list
/// because the admin views it on desktop.
class ThemeGrid extends StatelessWidget {
  const ThemeGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'App Theme',
      child: FillGrid(
        columns: 3,
        children: [
          for (final theme in kMockAppThemes)
            ThemeCard(theme: theme, isActive: theme.id == kActiveThemeId),
        ],
      ),
    );
  }
}
