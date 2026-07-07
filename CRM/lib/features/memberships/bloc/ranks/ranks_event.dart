import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/rank_preset_kind.dart';
import 'package:crm/features/memberships/data/models/rank_reorder_item.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

sealed class RanksEvent extends Equatable {
  const RanksEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the gym's rank ladder + sub-rank type + enabled
/// flag.
class RanksInitRequested extends RanksEvent {
  final String gymId;

  const RanksInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

class RankEnabledToggled extends RanksEvent {
  final String gymId;
  final bool isEnabled;

  const RankEnabledToggled({required this.gymId, required this.isEnabled});

  @override
  List<Object?> get props => [gymId, isEnabled];
}

class RankPresetSeeded extends RanksEvent {
  final String gymId;
  final RankPresetKind presetKind;

  const RankPresetSeeded({required this.gymId, required this.presetKind});

  @override
  List<Object?> get props => [gymId, presetKind];
}

class RanksReordered extends RanksEvent {
  final String gymId;
  final List<RankReorderItem> ranks;

  const RanksReordered({required this.gymId, required this.ranks});

  @override
  List<Object?> get props => [gymId, ranks];
}

/// Changes the gym's sub-rank type (stripes/div) directly,
/// independent of seeding a stripes/div preset.
class RankSubTypeChanged extends RanksEvent {
  final String gymId;
  final RankSubType type;

  const RankSubTypeChanged({required this.gymId, required this.type});

  @override
  List<Object?> get props => [gymId, type];
}
