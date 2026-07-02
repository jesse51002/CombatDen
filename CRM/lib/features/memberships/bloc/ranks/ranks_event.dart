import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/rank_create_request.dart';
import 'package:crm/features/memberships/data/models/rank_reorder_item.dart';
import 'package:crm/features/memberships/data/models/rank_update_data.dart';

sealed class RanksEvent extends Equatable {
  const RanksEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the gym's rank ladder + enabled flag.
class RanksInitRequested extends RanksEvent {
  final String gymId;

  const RanksInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

class RankCreated extends RanksEvent {
  final RankCreateRequest request;

  const RankCreated(this.request);

  @override
  List<Object?> get props => [request];
}

class RankUpdated extends RanksEvent {
  final String rankId;
  final RankUpdateData data;
  final String gymId;

  const RankUpdated({
    required this.rankId,
    required this.data,
    required this.gymId,
  });

  @override
  List<Object?> get props => [rankId, gymId];
}

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
  final String gymType;

  const RankPresetSeeded({required this.gymId, required this.gymType});

  @override
  List<Object?> get props => [gymId, gymType];
}

class RanksReordered extends RanksEvent {
  final String gymId;
  final List<RankReorderItem> ranks;

  const RanksReordered({required this.gymId, required this.ranks});

  @override
  List<Object?> get props => [gymId, ranks];
}

/// Rename a whole main-rank group (fan-out over its sub-rank rows).
class RankGroupRenamed extends RanksEvent {
  final String gymId;
  final List<String> rankIds;
  final String newName;

  const RankGroupRenamed({
    required this.gymId,
    required this.rankIds,
    required this.newName,
  });

  @override
  List<Object?> get props => [gymId, rankIds, newName];
}

/// Delete a whole main-rank group (its sub-rank rows, highest first).
class RankGroupDeleted extends RanksEvent {
  final String gymId;
  final List<String> rankIdsHighestSubFirst;

  const RankGroupDeleted({
    required this.gymId,
    required this.rankIdsHighestSubFirst,
  });

  @override
  List<Object?> get props => [gymId, rankIdsHighestSubFirst];
}
