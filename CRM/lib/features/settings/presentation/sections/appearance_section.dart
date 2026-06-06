import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

/// Appearance settings — the System / Light / Dark theme control.
///
/// The selection is read live from [themeController] (the app-wide source of
/// truth) and a tap dispatches [SettingsThemeModeChanged], which applies the
/// theme optimistically and persists it.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Appearance', style: DesignConstants.h1),
        const _ThemeModeControl(),
      ],
    );
  }
}

class _ThemeModeControl extends StatelessWidget {
  const _ThemeModeControl();

  // Pill order maps 1:1 to [_modes]; System first so the default reads first.
  static const List<ThemeMode> _modes = [
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];
  static const List<String> _labels = ['System', 'Light', 'Dark'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Choose your theme. “System” follows your device’s light or dark '
          'setting.',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        ListenableBuilder(
          listenable: themeController,
          builder: (context, _) => FilterPills(
            labels: _labels,
            selectedIndex: _modes.indexOf(themeController.mode),
            onSelected: (i) => context
                .read<SettingsBloc>()
                .add(SettingsThemeModeChanged(_modes[i])),
          ),
        ),
      ],
    );
  }
}
