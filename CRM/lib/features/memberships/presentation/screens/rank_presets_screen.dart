import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/models/rank_preset_kind.dart';
import 'package:crm/features/memberships/data/models/rank_preset_response.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/horizontal_scroller.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';
import 'package:crm/shared/widgets/warning_message.dart';

/// Seed a gym's ladder from a built-in preset. Pushed from the Ranks tab
/// with `BlocProvider.value(RanksBloc)` (so Apply reloads the ladder the
/// user returns to) and keeps the parent tab's URL. Previews each preset
/// ladder — belt art, names, and sub-position counts — before applying.
///
/// The merge is idempotent server-side (positions that already exist are
/// skipped), and seeding a stripes / division preset also copies that
/// preset's sub-rank type onto the gym.
class RankPresetsScreen extends StatefulWidget {
  final String gymId;

  const RankPresetsScreen({super.key, required this.gymId});

  @override
  State<RankPresetsScreen> createState() => _RankPresetsScreenState();
}

class _RankPresetsScreenState extends State<RankPresetsScreen> {
  late final Future<Map<RankPresetKind, List<RankPresetResponse>>>
      _presetsFuture;

  @override
  void initState() {
    super.initState();
    _presetsFuture =
        RanksRepository(apiClient: ApiClient()).listPresetsGrouped();
  }

  void _apply(RankPresetKind kind) {
    context
        .read<RanksBloc>()
        .add(RankPresetSeeded(gymId: widget.gymId, presetKind: kind));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ranksState = context.watch<RanksBloc>().state;
    final hasExisting = ranksState is RanksLoaded && ranksState.ranks.isNotEmpty;

    return AppShell(
      activeRoute: AppRoutes.memberships,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                _BackButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    Text('Seed from a preset', style: DesignConstants.h1),
                    Text(
                      'Start from a ready-made ladder, then tune it. '
                      'Existing ranks are kept; only missing positions '
                      'are added.',
                      style: DesignConstants.p.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                  ],
                ),
                if (hasExisting)
                  const WarningMessage(
                    message: 'You already have a ladder. Applying a preset '
                        'merges its belts in; positions you already have '
                        'are skipped.',
                  ),
                FutureBuilder<Map<RankPresetKind, List<RankPresetResponse>>>(
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
                    return _Presets(
                      grouped: snapshot.data!,
                      onApply: _apply,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Presets extends StatelessWidget {
  final Map<RankPresetKind, List<RankPresetResponse>> grouped;
  final void Function(RankPresetKind kind) onApply;

  const _Presets({required this.grouped, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final entries = grouped.entries
        .where((e) => e.key != RankPresetKind.unknown && e.value.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (final entry in entries)
          _PresetCard(
            kind: entry.key,
            ranks: entry.value,
            onApply: () => onApply(entry.key),
          ),
      ],
    );
  }
}

/// One preset ladder as an object card: title, a count summary, a
/// horizontal preview of its belts, and an Apply action.
class _PresetCard extends StatelessWidget {
  final RankPresetKind kind;
  final List<RankPresetResponse> ranks;
  final VoidCallback onApply;

  const _PresetCard({
    required this.kind,
    required this.ranks,
    required this.onApply,
  });

  String get _summary {
    final belts = ranks.length;
    RankSubType? impliedType;
    for (final r in ranks) {
      if (r.impliedSubRankType != null) {
        impliedType = r.impliedSubRankType;
        break;
      }
    }
    final beltLabel = '$belts ${belts == 1 ? 'belt' : 'belts'}';
    return switch (impliedType) {
      RankSubType.stripes => '$beltLabel · with stripes',
      RankSubType.div => '$beltLabel · with divisions',
      _ => beltLabel,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingTiny,
                  children: [
                    Text(kind.displayLabel, style: DesignConstants.h2),
                    Text(
                      _summary,
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                  ],
                ),
              ),
              AppPrimaryButton(
                text: 'Apply',
                borderRadius: DesignConstants.radiusSmall,
                onPressed: onApply,
              ),
            ],
          ),
          HorizontalScroller(
            spacing: DesignConstants.spacingLarge,
            children: [
              for (final rank in ranks)
                _BeltPreview(name: rank.name, imageUrl: rank.imageUrl),
            ],
          ),
        ],
      ),
    );
  }
}

class _BeltPreview extends StatelessWidget {
  final String name;
  final String? imageUrl;

  const _BeltPreview({required this.name, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          RankBeltImage(imageUrl: imageUrl, size: 60),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DesignConstants.pSmall,
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.spacingSmall),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                Symbols.arrow_back_sharp,
                size: DesignConstants.iconSizeMedium,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text,
              ),
              Text('Ranks', style: DesignConstants.h3),
            ],
          ),
        ),
      ),
    );
  }
}
