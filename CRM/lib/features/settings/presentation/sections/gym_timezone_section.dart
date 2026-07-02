import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/presentation/dialogs/timezone_picker_dialog.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/form/tappable_field.dart';

/// Max width of the timezone field — a settings control shouldn't stretch
/// the whole page (matches the login form's field cap).
const double _kSelectorMaxWidth = 480;

/// Settings section for the gym's IANA timezone.
///
/// The field shows the current zone with its live UTC offset; tapping it
/// opens [TimezonePickerDialog] — a searchable picker over the FULL IANA
/// database (offsets shown, sorted by offset then name). A pick confirms
/// via [ConfirmationModal], then dispatches [SettingsTimezoneChanged]. The
/// save is NOT optimistic: the field keeps showing the current zone (from
/// [selectedGym]) until the backend commits — success flips the value and
/// surfaces a SnackBar; failure surfaces through the screen's shared error
/// listener.
class GymTimezoneSection extends StatelessWidget {
  const GymTimezoneSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (prev, curr) =>
          curr.timezoneSavedCount > prev.timezoneSavedCount,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Gym timezone updated')),
          );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('Gym timezone', style: DesignConstants.h1),
          Text(
            'Class times, the schedule board, and check-in windows follow '
            'this zone. Changing it doesn\'t rewrite past classes — upcoming '
            'classes keep their local times in the new zone.',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          const _TimezoneSelector(),
        ],
      ),
    );
  }
}

/// The pick → confirm → save flow around the read-only field. Stateless: the
/// displayed value always comes from [selectedGym], so the non-optimistic
/// save needs no local reset bookkeeping.
class _TimezoneSelector extends StatelessWidget {
  const _TimezoneSelector();

  Future<void> _pick(BuildContext context, String? current) async {
    final picked = await TimezonePickerDialog.show(
      context: context,
      current: current,
    );
    if (picked == null || picked == current || !context.mounted) return;
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Change gym timezone?',
      message: 'Change gym timezone to ${zoneDisplayLabel(picked)}? '
          'The schedule will show times in this zone from now on.',
      confirmLabel: 'Change timezone',
    );
    if (!confirmed || !context.mounted) return;
    context.read<SettingsBloc>().add(SettingsTimezoneChanged(picked));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        final current = selectedGym.timezone;
        return BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (prev, curr) =>
              prev.savingTimezone != curr.savingTimezone,
          builder: (context, state) {
            return Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kSelectorMaxWidth,
                  ),
                  child: _TimezoneField(
                    current: current,
                    enabled: !state.savingTimezone,
                    onTap: () => _pick(context, current),
                  ),
                ),
                if (state.savingTimezone) const AppSpinner(),
              ],
            );
          },
        );
      },
    );
  }
}

/// The read-only field showing the current zone + its live UTC offset. The
/// offset needs the tz database, whose lazy load is kicked here (memoized —
/// never at app startup); until it's ready the bare zone id shows.
class _TimezoneField extends StatelessWidget {
  final String? current;
  final bool enabled;
  final VoidCallback onTap;

  const _TimezoneField({
    required this.current,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: ensureTimezonesInitialized(),
      builder: (context, snapshot) {
        final ready = snapshot.connectionState == ConnectionState.done;
        final zone = current;
        return TappableField(
          valueText:
              zone == null ? null : (ready ? zoneDisplayLabel(zone) : zone),
          hintText: 'Select a timezone',
          icon: Symbols.public_sharp,
          onTap: enabled ? onTap : () {},
        );
      },
    );
  }
}
