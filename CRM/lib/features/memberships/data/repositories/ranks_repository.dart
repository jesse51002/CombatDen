import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/main_rank_create_request.dart';
import 'package:crm/features/memberships/data/models/main_rank_update_data.dart';
import 'package:crm/features/memberships/data/models/promotion_choice.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/models/rank_member_response.dart';
import 'package:crm/features/memberships/data/models/rank_member_row.dart';
import 'package:crm/features/memberships/data/models/rank_preset_kind.dart';
import 'package:crm/features/memberships/data/models/rank_preset_response.dart';
import 'package:crm/features/memberships/data/models/rank_ready_row.dart';
import 'package:crm/features/memberships/data/models/rank_reorder_item.dart';
import 'package:crm/features/memberships/data/models/rank_sub_rank_counts.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

/// Repository for the gym's two-level rank ladder + per-member rank
/// changes — the `/api/v1/ranks` backend domain. Every call goes
/// through [ApiClient]; paths/shapes match
/// `FastApiBackend/src/ranks`.
class RanksRepository {
  final ApiClient _apiClient;

  RanksRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  // ----- Ladder CRUD -----

  /// `GET /api/v1/ranks/?gym_id=…` — the ordered main-rank ladder
  /// plus the gym's [RankSubType].
  Future<RankLadder> listRanks(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/ranks/',
      queryParameters: {'gym_id': gymId},
    );
    final data = response.data as Map<String, dynamic>;
    return RankLadder(
      ranks: _mainRanks(data['items']),
      subRankType: RankSubType.fromJson(data['sub_rank_type'] as String),
    );
  }

  /// `GET /api/v1/ranks/{rank_id}` — a single main rank (the rank
  /// detail screen's header read).
  Future<MainRank> getRank(String rankId) async {
    final response = await _apiClient.get('/api/v1/ranks/$rankId');
    return MainRank.fromJson(response.data as Map<String, dynamic>);
  }

  /// `POST /api/v1/ranks/`.
  Future<MainRank> createRank(MainRankCreateRequest req) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/',
      data: req.toJson(),
    );
    return MainRank.fromJson(response.data as Map<String, dynamic>);
  }

  /// `PUT /api/v1/ranks/{rank_id}` (mutable fields nested under
  /// `data`). Also the fold-target for what used to be the
  /// stand-alone whole-group rename (a group is just one row now —
  /// renaming it is an ordinary update).
  Future<MainRank> updateRank(
    String rankId,
    MainRankUpdateData data,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/ranks/$rankId',
      data: {'data': data.toJson()},
    );
    return MainRank.fromJson(response.data as Map<String, dynamic>);
  }

  /// `DELETE /api/v1/ranks/{rank_id}` — the backend reassigns
  /// affected members to a neighbour rank's base leaf, then deletes.
  /// Also the fold-target for what used to be the stand-alone
  /// whole-group delete.
  Future<void> deleteRank(String rankId) async {
    await _apiClient.delete('/api/v1/ranks/$rankId');
  }

  // ----- Enable toggle -----

  /// `GET /api/v1/ranks/enabled?gym_id=…`.
  Future<RankEnabledResponse> getRankEnabled(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/ranks/enabled',
      queryParameters: {'gym_id': gymId},
    );
    return RankEnabledResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `PUT /api/v1/ranks/enabled` — false→true backfills rank-less
  /// members to the lowest rank.
  Future<RankEnabledResponse> setRankEnabled(
    String gymId,
    bool enabled,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/ranks/enabled',
      data: {'gym_id': gymId, 'is_rank_enabled': enabled},
    );
    return RankEnabledResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ----- Sub-rank type -----

  /// The gym's current [RankSubType]. There is no dedicated read
  /// endpoint for this alone — it rides along on every
  /// `GET /api/v1/ranks/` response, so this is a thin convenience
  /// over [listRanks] for a caller that only wants the type.
  Future<RankSubType> getSubRankType(String gymId) async {
    final ladder = await listRanks(gymId);
    return ladder.subRankType;
  }

  /// Sets the gym's [RankSubType] directly (independent of seeding a
  /// stripes/div preset, which also sets it as a side effect).
  ///
  /// Rides the ordinary gym-update path: `PUT /api/v1/gyms/{gym_id}`'s
  /// `GymUpdateData` accepts `sub_rank_type` (a mutable gym column).
  /// Send a concrete `none`/`stripes`/`div` value (`type.toJson()`),
  /// never an explicit null — the column is `NOT NULL DEFAULT 'stripes'`.
  /// `none` turns sub-positions off gym-wide (the backend drops members
  /// to no sub-index).
  Future<void> setSubRankType(String gymId, RankSubType type) async {
    await _apiClient.put(
      '/api/v1/gyms/$gymId',
      data: {
        'data': {'sub_rank_type': type.toJson()},
      },
    );
  }

  // ----- Presets + reorder -----

  /// `POST /api/v1/ranks/from-preset` — idempotent merge; also
  /// copies the preset's implied sub-rank type onto the gym. Returns
  /// the gym's full ladder afterwards.
  Future<RankLadder> seedFromPreset(
    String gymId,
    RankPresetKind presetKind,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/from-preset',
      data: {'gym_id': gymId, 'preset_kind': presetKind.toJson()},
    );
    final data = response.data as Map<String, dynamic>;
    return RankLadder(
      ranks: _mainRanks(data['items']),
      subRankType: RankSubType.fromJson(data['sub_rank_type'] as String),
    );
  }

  /// `GET /api/v1/ranks/presets/grouped` — every preset ladder
  /// (flat main rows), keyed by [RankPresetKind].
  Future<Map<RankPresetKind, List<RankPresetResponse>>>
      listPresetsGrouped() async {
    final response = await _apiClient.get('/api/v1/ranks/presets/grouped');
    final presets =
        (response.data as Map<String, dynamic>)['presets']
            as Map<String, dynamic>;
    return presets.map(
      (kind, rows) => MapEntry(
        RankPresetKind.fromJson(kind),
        (rows as List<dynamic>)
            .map(
              (e) => RankPresetResponse.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// `POST /api/v1/ranks/reorder` — applies a full new main-rank
  /// ordering atomically; returns the reordered ladder.
  Future<RankLadder> reorderRanks(
    String gymId,
    List<RankReorderItem> ranks,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/reorder',
      data: {
        'gym_id': gymId,
        'ranks': ranks.map((e) => e.toJson()).toList(),
      },
    );
    final data = response.data as Map<String, dynamic>;
    return RankLadder(
      ranks: _mainRanks(data['items']),
      subRankType: RankSubType.fromJson(data['sub_rank_type'] as String),
    );
  }

  // ----- Paginated member reads -----

  /// `GET /api/v1/ranks/{rank_id}/members` — members currently on
  /// [rankId], ordered by sub-index then name.
  Future<(List<RankMemberRow> items, int totalCount)> membersInRank(
    String gymId,
    String rankId, {
    int startIndex = 0,
    int count = 25,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/ranks/$rankId/members',
      queryParameters: {
        'gym_id': gymId,
        'start_index': startIndex,
        'count': count,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>)
        .map((e) => RankMemberRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items, data['total_count'] as int);
  }

  /// `GET /api/v1/ranks/{rank_id}/sub-rank-counts?gym_id=…` — the
  /// member headcount on [rankId] broken down by sub-position (total +
  /// a sparse per-`sub_index` list). Drives the rank-detail counts
  /// summary.
  Future<RankSubRankCounts> subRankCounts(
    String gymId,
    String rankId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/ranks/$rankId/sub-rank-counts',
      queryParameters: {'gym_id': gymId},
    );
    return RankSubRankCounts.fromJson(response.data as Map<String, dynamic>);
  }

  /// `GET /api/v1/ranks/ready-to-promote` — the proximity-sorted
  /// board of members closest to their next leaf.
  Future<(List<RankReadyRow> items, int totalCount)> readyToPromote(
    String gymId, {
    int startIndex = 0,
    int count = 25,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/ranks/ready-to-promote',
      queryParameters: {
        'gym_id': gymId,
        'start_index': startIndex,
        'count': count,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>)
        .map((e) => RankReadyRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items, data['total_count'] as int);
  }

  // ----- Per-member rank changes -----

  /// `POST /api/v1/ranks/promote-member` — advances the member one
  /// leaf up the ordered ladder (the next sub-position within their
  /// current main rank, else the base leaf of the next main rank; a
  /// rank-less member is assigned the lowest leaf). NOTE: the real
  /// backend request carries only `gym_id` + `member_id` — there is
  /// no `kind` parameter; "promote to next major, skipping remaining
  /// subs" is not a single backend call, so it's resolved client-side
  /// in [applyPromotion] via [setMemberRank] instead.
  Future<RankMemberResponse> promoteMember(
    String gymId,
    String memberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/promote-member',
      data: {'gym_id': gymId, 'member_id': memberId},
    );
    return RankMemberResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `POST /api/v1/ranks/set-member-rank` — sets an explicit leaf
  /// (correction / demotion / assignment), or `null` [rankId] to
  /// unassign.
  Future<RankMemberResponse> setMemberRank(
    String gymId,
    String memberId, {
    String? rankId,
    int? subIndex,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/set-member-rank',
      data: {
        'gym_id': gymId,
        'member_id': memberId,
        'rank_id': rankId,
        'sub_index': subIndex,
      },
    );
    return RankMemberResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Applies a staff-picked [PromotionChoice] via whichever real
  /// endpoint it maps to:
  ///  - [PromoteNextSub] → [promoteMember] directly.
  ///  - [PromoteExplicit] → [setMemberRank] with its ids as given.
  ///  - [PromoteNextMajor] → there is no backend "skip to next major"
  ///    call, so this resolves the target itself: the next main rank
  ///    after [currentMainRankId] in [ladder] (ordered by
  ///    `main_rank_num_order`, exactly as the backend returns it),
  ///    then [setMemberRank]s to that rank's base leaf (sub-index `0`
  ///    when it has sub-ranks, else `null` — mirrors the backend's
  ///    own base-leaf rule). A `null` [currentMainRankId] (a
  ///    rank-less member) resolves to the ladder's lowest rank,
  ///    mirroring [promoteMember]'s rank-less behaviour. Throws
  ///    [StateError] when [currentMainRankId] is already the top of
  ///    [ladder] (mirrors the backend's own "highest rank" 409).
  Future<RankMemberResponse> applyPromotion({
    required String gymId,
    required String memberId,
    required PromotionChoice choice,
    String? currentMainRankId,
    List<MainRank> ladder = const [],
  }) {
    switch (choice) {
      case PromoteNextSub():
        return promoteMember(gymId, memberId);
      case PromoteExplicit(:final mainRankId, :final subIndex):
        return setMemberRank(
          gymId,
          memberId,
          rankId: mainRankId,
          subIndex: subIndex,
        );
      case PromoteNextMajor():
        final next = _nextMainRank(ladder, currentMainRankId);
        return setMemberRank(
          gymId,
          memberId,
          rankId: next.rankId,
          subIndex: next.subRankCount > 0 ? 0 : null,
        );
    }
  }

  /// The next main rank after [currentMainRankId] in the ordered
  /// [ladder] — the lowest rank when [currentMainRankId] is `null`
  /// (rank-less) or not found in the ladder.
  MainRank _nextMainRank(List<MainRank> ladder, String? currentMainRankId) {
    if (ladder.isEmpty) {
      throw StateError('Gym has no ranks configured');
    }
    if (currentMainRankId == null) return ladder.first;
    final index = ladder.indexWhere((r) => r.rankId == currentMainRankId);
    if (index < 0) return ladder.first;
    if (index >= ladder.length - 1) {
      throw StateError('Member is already at the highest main rank');
    }
    return ladder[index + 1];
  }

  List<MainRank> _mainRanks(dynamic items) {
    return (items as List<dynamic>)
        .map((e) => MainRank.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
