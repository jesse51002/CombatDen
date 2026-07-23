import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/data/repositories/settings_repository.dart';
import 'package:crm/features/settings/presentation/sections/appearance_section.dart';
import 'package:crm/features/settings/presentation/sections/gym_presets_section.dart';
import 'package:crm/features/settings/presentation/sections/gym_profile_section.dart';
import 'package:crm/features/settings/presentation/sections/gym_timezone_section.dart';
import 'package:crm/features/settings/presentation/sections/qr_codes_section.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Settings — the gym admin's per-account preferences.
///
/// Sections sit directly on the page, separated by hairlines (the De-Card
/// rule). Each section is **role-gated** (see [RolePolicy]); a role that can't
/// use a section never sees it, and the hairlines interleave only the visible
/// ones:
///   1. Gym profile — the gym's name + uploaded logo (staff admin only)
///   2. Appearance — the System / Light / Dark theme control (any staff)
///   3. Gym timezone — the gym's IANA zone (staff admin only)
///   4. Sign-up QR codes — the printable front-desk codes (kiosk or gym
///      settings, so front desk sees them)
///   5. Gym presets — the owner1-only template import (self-gated)
///
/// Front desk lands on appearance + QR only; trainer never reaches this
/// screen (the route guard blocks `/settings` for it).
///
/// Backed by a small [SettingsBloc] (the theme, timezone, and Gym profile
/// saves talk to the backend); the selected theme itself lives in
/// `themeController` and drives the whole app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = selectedGym.role;
    final canGymSettings = role?.canManageGymSettings ?? false;
    final canAppearance = role?.canUseAppearanceSettings ?? false;
    final canKiosk = role?.canOperateKiosk ?? false;

    // Only the sections this role may use, joined by hairlines with no
    // leading / trailing / doubled separator.
    final sections = <Widget>[
      if (canGymSettings) const GymProfileSection(),
      if (canAppearance) const AppearanceSection(),
      if (canGymSettings) const GymTimezoneSection(),
      if (canKiosk || canGymSettings) const QrCodesSection(),
      if (GymPresetsSection.isVisible()) const GymPresetsSection(),
    ];
    final children = <Widget>[
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const Hairline(),
        sections[i],
      ],
    ];

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
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
