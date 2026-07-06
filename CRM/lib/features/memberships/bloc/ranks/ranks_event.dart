import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/main_rank_create_request.dart';
import 'package:crm/features/memberships/data/models/main_rank_update_data.dart';
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

class RankCreated extends RanksEvent {
  final MainRankCreateRequest request;

  const RankCreated(this.request);

  @override
  List<Object?> get props => [request];
}

/// Updates a rank's mutable fields. A whole-group rename (one main
/// rank IS the group now) is just a name-only update through this
/// same event.
class RankUpdated extends RanksEvent {
  final String rankId;
  final MainRankUpdateData data;
  final String gymId;

  const RankUpdated({
    required this.rankId,
    required this.data,
    required this.gymId,
  });

  @override
  List<Object?> get props => [rankId, gymId];
}

/// Deletes a rank (the backend reassigns its members to a neighbour
/// rank's base leaf first). Also the fold-target for what used to
/// be the stand-alone whole-group delete.
class RankDeleted extends RanksEvent {
  final String rankId;
  final String gymId;

  const RankDeleted({required this.rankId, required this.gymId});

  @override
  List<Object?> get props => [rankId, gymId];
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
