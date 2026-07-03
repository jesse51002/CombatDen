import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/data/repositories/settings_repository.dart';
import 'package:crm/features/settings/presentation/sections/gym_profile_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// Width cap for the dialog — the editor is a single stacked column
/// (name field above the logo picker), so it reads best narrow.
const double _kDialogMaxWidth = 560;

/// The shared Gym profile editor ([GymProfileSection]) hosted in a dialog —
/// opened from the Theme tab's "Edit gym name / logo" button under the phone
/// preview. Owns its own [SettingsBloc] (the Theme tab has none) and, like
/// the Settings screen, surfaces save FAILURES via a SnackBar; the section
/// itself surfaces the SUCCESS SnackBar and the dialog closes on it.
///
/// Only constructed in the admin context (the button never renders in the
/// public standalone theme browser), so no Supabase-backed bloc is ever
/// built there.
class GymProfileDialog extends StatelessWidget {
  const GymProfileDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const GymProfileDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<SettingsRepository>(
      create: (_) => SettingsRepository(apiClient: ApiClient()),
      child: BlocProvider<SettingsBloc>(
        create: (ctx) =>
            SettingsBloc(repository: ctx.read<SettingsRepository>()),
        child: BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (prev, curr) =>
              curr.error != null && prev.error != curr.error,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.error!)));
            context.read<SettingsBloc>().add(const SettingsErrorCleared());
          },
          child: Builder(
            builder: (context) => AppDialog(
              title: 'Gym profile',
              maxWidth: _kDialogMaxWidth,
              body: GymProfileSection(
                showHeader: false,
                onSaved: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
