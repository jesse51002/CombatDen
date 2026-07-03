import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/bloc/set_app_theme_bloc.dart';
import 'package:crm/features/members/bloc/set_app_theme_event.dart';
import 'package:crm/features/members/bloc/set_app_theme_state.dart';
import 'package:crm/features/members/data/gym_theme_repository.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:theme_flutter/customization_runtime.dart';

/// The admin-only "Set as app theme" action beneath the phone preview: persists
/// the currently-previewed ThemeService design as the gym's saved branding
/// (`gyms.theme_design_id`). Self-hides in the public standalone browser (no
/// real gym to persist to). Shows a disabled checkmark state once the previewed
/// design is already the saved one.
class SetAppThemeButton extends StatelessWidget {
  const SetAppThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Admin-only: no real gym → nothing to persist to (also keeps the public
    // browser from ever constructing the authed ApiClient).
    if (selectedGym.gymId == null) return const SizedBox.shrink();
    return BlocProvider(
      create: (_) =>
          SetAppThemeBloc(repository: GymThemeRepository(ApiClient())),
      child: const _SetAppThemeButtonView(),
    );
  }
}

class _SetAppThemeButtonView extends StatelessWidget {
  const _SetAppThemeButtonView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SetAppThemeBloc, SetAppThemeState>(
      listenWhen: (prev, curr) =>
          curr.savedCount > prev.savedCount ||
          (curr.error != null && curr.error != prev.error),
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);
        if (state.error != null) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.error!)));
          context.read<SetAppThemeBloc>().add(const SetAppThemeErrorCleared());
        } else if (state.savedCount > 0) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('App theme saved')),
            );
        }
      },
      builder: (context, state) {
        // Re-render on a theme switch (the previewed design) and on a save
        // (savedThemeDesignId flips the checkmark state).
        return ListenableBuilder(
          listenable: ThemeRuntime.isReady
              ? Listenable.merge([selectedGym, ThemeRuntime.changes])
              : selectedGym,
          builder: (context, _) {
            final current = ThemeRuntime.isReady
                ? ThemeRuntime.activeDesignId
                : selectedGym.designId;
            if (current == null || current.isEmpty) {
              return const SizedBox.shrink();
            }
            final isCurrent = current == selectedGym.savedThemeDesignId;
            if (isCurrent) {
              return AppPrimaryButton(
                text: 'Current app theme',
                icon: Icon(
                  Symbols.check_sharp,
                  color: DesignConstants.onAccent,
                  weight: DesignConstants.iconWeight,
                  size: DesignConstants.iconSizeSmall,
                ),
                // Disabled: already saved (the button dims via its own opacity).
                onPressed: null,
              );
            }
            return AppPrimaryButton(
              text: 'Set as app theme',
              isLoading: state.saving,
              onPressed: state.saving
                  ? null
                  : () => context
                      .read<SetAppThemeBloc>()
                      .add(SetAppThemeRequested(current)),
            );
          },
        );
      },
    );
  }
}
