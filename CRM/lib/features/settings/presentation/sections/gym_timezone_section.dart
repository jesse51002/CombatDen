import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// Max width of the timezone selector — a settings control shouldn't stretch
/// the whole page (matches the login form's field cap).
const double _kSelectorMaxWidth = 480;

/// One curated timezone choice: a friendly label + its IANA zone id.
class _Zone {
  final String label;
  final String id;

  const _Zone(this.label, this.id);

  /// How the zone reads in the dropdown and the confirm copy.
  String get displayLabel => '$label ($id)';
}

/// The curated US zones offered by default. If the gym's current zone isn't
/// one of these, it's appended as its own entry so the saved value always
/// displays.
const List<_Zone> _kZones = [
  _Zone('Eastern', 'America/New_York'),
  _Zone('Central', 'America/Chicago'),
  _Zone('Mountain', 'America/Denver'),
  _Zone('Arizona', 'America/Phoenix'),
  _Zone('Pacific', 'America/Los_Angeles'),
  _Zone('Alaska', 'America/Anchorage'),
  _Zone('Hawaii', 'Pacific/Honolulu'),
];

/// Settings section for the gym's IANA timezone.
///
/// Selecting a different zone confirms via [ConfirmationModal], then
/// dispatches [SettingsTimezoneChanged]. The save is NOT optimistic: the
/// selector keeps showing the current zone (from [selectedGym]) until the
/// backend commits — success flips the value and surfaces a SnackBar; failure
/// surfaces through the screen's shared error listener.
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

/// The confirm-then-save selector. Stateful only for [_resetTick], which
/// re-keys the dropdown after a cancelled or dispatched pick so its internal
/// selection snaps back to the real (not-yet-changed) value — the dropdown
/// otherwise keeps showing the picked option even though the save is
/// non-optimistic.
class _TimezoneSelector extends StatefulWidget {
  const _TimezoneSelector();

  @override
  State<_TimezoneSelector> createState() => _TimezoneSelectorState();
}

class _TimezoneSelectorState extends State<_TimezoneSelector> {
  int _resetTick = 0;

  /// The offered zones: the curated list, plus the gym's current zone as its
  /// own entry when it isn't curated (so the saved value always displays).
  List<_Zone> _zonesFor(String? current) {
    if (current == null || _kZones.any((z) => z.id == current)) {
      return _kZones;
    }
    return [..._kZones, _Zone(current, current)];
  }

  Future<void> _onPicked(String? zoneId, String? current) async {
    if (zoneId == null || zoneId == current) return;
    final zone = _zonesFor(current).firstWhere((z) => z.id == zoneId);
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Change gym timezone?',
      message: 'Change gym timezone to ${zone.displayLabel}? The schedule '
          'will show times in this zone from now on.',
      confirmLabel: 'Change timezone',
    );
    if (!mounted) return;
    // Re-key the dropdown either way: the save isn't optimistic, so until
    // the backend commits the selector must show the CURRENT zone again.
    setState(() => _resetTick++);
    if (!confirmed) return;
    context.read<SettingsBloc>().add(SettingsTimezoneChanged(zoneId));
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
                  child: AppDropdownField<String>(
                    key: ValueKey('$current-$_resetTick'),
                    value: current,
                    hintText: 'Select a timezone',
                    items: [
                      for (final zone in _zonesFor(current))
                        DropdownMenuItem<String>(
                          value: zone.id,
                          child: Text(zone.displayLabel),
                        ),
                    ],
                    onChanged: state.savingTimezone
                        ? null
                        : (zoneId) => _onPicked(zoneId, current),
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
