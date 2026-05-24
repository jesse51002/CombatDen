import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/gym_branding_section.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_grid.dart';

/// Theme tab: gym branding (logo + name) on top, then the theme picker.
class ThemeTab extends StatelessWidget {
  const ThemeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: const [GymBrandingSection(), ThemeGrid()],
    );
  }
}
