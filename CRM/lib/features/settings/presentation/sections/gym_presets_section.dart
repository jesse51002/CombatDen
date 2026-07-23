import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/presets/bloc/presets_bloc.dart';
import 'package:crm/features/presets/bloc/presets_event.dart';
import 'package:crm/features/presets/bloc/presets_state.dart';
import 'package:crm/features/presets/data/repositories/presets_repository.dart';
import 'package:crm/features/settings/presentation/sections/gym_presets_content.dart';

/// The email that may access the preset import tool.
/// The backend enforces this allowlist server-side as well.
const String kPresetAdminEmail = 'owner1@test.com';

/// Settings section that lets the preset admin apply a video / classes /
/// rewards template to the current real gym.
///
/// GATED: only rendered when the current user's email is [kPresetAdminEmail]
/// AND their role at the active gym may manage gym settings (owner / admin,
/// via [RolePolicy.canManageGymSettings]). The backend also enforces the
/// allowlist — the gate is a UI convenience only. Exposed as [isVisible] so
/// the Settings screen can omit the section (and its leading hairline)
/// entirely rather than render an invisible placeholder.
class GymPresetsSection extends StatelessWidget {
  const GymPresetsSection({super.key});

  /// Whether the preset import tool is available to the current user.
  static bool isVisible() {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final role = selectedGym.role;
    return email == kPresetAdminEmail &&
        (role?.canManageGymSettings ?? false);
  }

  @override
  Widget build(BuildContext context) {
    if (!isVisible()) {
      return const SizedBox.shrink();
    }

    return RepositoryProvider<PresetsRepository>(
      create: (_) => PresetsRepository(apiClient: ApiClient()),
      child: BlocProvider<PresetsBloc>(
        create: (ctx) => PresetsBloc(
          repository: ctx.read<PresetsRepository>(),
        )..add(const PresetsTemplatesRequested()),
        child: BlocListener<PresetsBloc, PresetsState>(
          listenWhen: (prev, curr) =>
              curr.error != null && prev.error != curr.error,
          listener: (ctx, state) {
            ScaffoldMessenger.of(ctx)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.error!)));
            ctx.read<PresetsBloc>().add(const PresetsErrorCleared());
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingLarge,
            children: [
              Text('Gym presets', style: DesignConstants.h1),
              const _PresetsDescription(),
              const GymPresetsContent(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetsDescription extends StatelessWidget {
  const _PresetsDescription();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Apply a curated template to this gym — videos, classes, rewards, and '
      'theme — in one step. The gym\'s existing content is replaced.',
      style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
    );
  }
}
