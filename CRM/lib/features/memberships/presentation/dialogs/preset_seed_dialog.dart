import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/data/models/rank_preset_group.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_color.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/warning_message.dart';

/// Seed a gym's ladder from a built-in preset (bjj / mma / generic).
/// Side-reads the grouped presets, lets the user preview a type's
/// ranks, then applies it. The merge is idempotent — existing
/// positions are skipped server-side.
class PresetSeedDialog extends StatefulWidget {
  final RanksBloc bloc;
  final RanksRepository repository;
  final String gymId;
  final bool hasExistingRanks;

  const PresetSeedDialog({
    super.key,
    required this.bloc,
    required this.repository,
    required this.gymId,
    required this.hasExistingRanks,
  });

  static Future<void> show({
    required BuildContext context,
    required RanksBloc bloc,
    required RanksRepository repository,
    required String gymId,
    required bool hasExistingRanks,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PresetSeedDialog(
        bloc: bloc,
        repository: repository,
        gymId: gymId,
        hasExistingRanks: hasExistingRanks,
      ),
    );
  }

  @override
  State<PresetSeedDialog> createState() => _PresetSeedDialogState();
}

class _PresetSeedDialogState extends State<PresetSeedDialog> {
  late final Future<Map<String, List<RankPresetGroup>>> _presetsFuture;
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _presetsFuture = widget.repository.listPresetsGrouped();
  }

  String _typeLabel(String key) =>
      key.length <= 3 ? key.toUpperCase() : '${key[0].toUpperCase()}${key.substring(1)}';

  void _apply() {
    widget.bloc.add(RankPresetSeeded(
      gymId: widget.gymId,
      gymType: _selectedType!,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Seed from Preset',
      body: FutureBuilder<Map<String, List<RankPresetGroup>>>(
        future: _presetsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(DesignConstants.paddingBig),
              child: Center(child: AppSpinner()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const ErrorMessage(
              message: 'Could not load presets. Try again.',
            );
          }
          return _content(snapshot.data!);
        },
      ),
      actions: AppDialogActions(
        primaryLabel: 'Apply',
        primaryOnPressed: _selectedType == null ? null : _apply,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _content(Map<String, List<RankPresetGroup>> presets) {
    final types = presets.keys.toList();
    final selected = _selectedType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (widget.hasExistingRanks)
          const WarningMessage(
            message: 'This adds preset ranks to your existing ladder. '
                'Ranks whose position already exists are skipped.',
          ),
        AppDropdownField<String>(
          label: 'Discipline',
          value: selected,
          hintText: 'Choose a preset',
          items: [
            for (final type in types)
              DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
          ],
          onChanged: (v) => setState(() => _selectedType = v),
        ),
        if (selected != null) _Preview(groups: presets[selected]!),
      ],
    );
  }
}

/// Read-only preview of a preset's main ranks with sub-ranks nested.
class _Preview extends StatelessWidget {
  final List<RankPresetGroup> groups;

  const _Preview({required this.groups});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final group in groups)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(group.mainName, style: DesignConstants.h3),
              for (final sub in group.subRanks)
                Padding(
                  padding: const EdgeInsets.only(
                    left: DesignConstants.paddingBig,
                  ),
                  child: Row(
                    spacing: DesignConstants.spacingSmall,
                    children: [
                      RankColorSwatch(
                        color: sub.color,
                        size: DesignConstants.iconSizeSmall,
                      ),
                      Text(sub.subName, style: DesignConstants.pSmall),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
