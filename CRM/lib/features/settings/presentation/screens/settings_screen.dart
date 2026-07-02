import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/data/repositories/settings_repository.dart';
import 'package:crm/features/settings/presentation/sections/appearance_section.dart';
import 'package:crm/features/settings/presentation/sections/gym_presets_section.dart';
import 'package:crm/features/settings/presentation/sections/gym_timezone_section.dart';
import 'package:crm/features/settings/presentation/sections/qr_codes_section.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Settings — the gym admin's per-account preferences.
///
/// Sections sit directly on the page, separated by hairlines (the De-Card
/// rule):
///   1. Appearance — the System / Light / Dark theme control
///   2. Gym timezone — the gym's IANA zone (drives class times, the schedule
///      board, and check-in windows)
///   3. Sign-up QR codes — the printable front-desk codes (moved here from the
///      nav rail)
///   4. Gym presets — the owner1-only template import
///
/// Backed by a small [SettingsBloc] (the theme + timezone saves talk to the
/// backend); the selected theme itself lives in `themeController` and drives
/// the whole app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<SettingsRepository>(
      create: (_) => SettingsRepository(apiClient: ApiClient()),
      child: BlocProvider<SettingsBloc>(
        create: (ctx) => SettingsBloc(
          repository: ctx.read<SettingsRepository>(),
        ),
        child: AppShell(
          activeRoute: AppRoutes.settings,
          child: BlocListener<SettingsBloc, SettingsState>(
            listenWhen: (prev, curr) =>
                curr.error != null && prev.error != curr.error,
            listener: (context, state) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.error!)));
              context.read<SettingsBloc>().add(const SettingsErrorCleared());
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DesignConstants.paddingBig),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingBig,
                children: const [
                  AppearanceSection(),
                  Hairline(),
                  GymTimezoneSection(),
                  Hairline(),
                  QrCodesSection(),
                  Hairline(),
                  GymPresetsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
