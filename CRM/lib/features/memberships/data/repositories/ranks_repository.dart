import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/memberships/data/models/rank_create_request.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/data/models/rank_preset_group.dart';
import 'package:crm/features/memberships/data/models/rank_reorder_item.dart';
import 'package:crm/features/memberships/data/models/rank_update_data.dart';

/// Repository for the gym's rank ladder + per-member rank changes —
/// the `/api/v1/ranks` backend domain. Every call goes through
/// [ApiClient]; paths/shapes match `FastApiBackend/src/ranks`.
class RanksRepository {
  final ApiClient _apiClient;

  RanksRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  // ----- Ladder CRUD -----

  /// `GET /api/v1/ranks/?gym_id=…` — the ordered ladder.
  Future<List<RankFullResponse>> listRanks(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/ranks/',
      queryParameters: {'gym_id': gymId},
    );
    return _items(response.data);
  }

  /// `POST /api/v1/ranks/`.
  Future<RankFullResponse> createRank(RankCreateRequest req) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/',
      data: req.toJson(),
    );
    return RankFullResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `PUT /api/v1/ranks/{rank_id}` (mutable fields nested under `data`).
  Future<RankFullResponse> updateRank(
    String rankId,
    RankUpdateData data,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/ranks/$rankId',
      data: {'data': data.toJson()},
    );
    return RankFullResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `DELETE /api/v1/ranks/{rank_id}` — backend reassigns affected
  /// members to a neighbour rank, then deletes.
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

  // ----- Presets + reorder -----

  /// `POST /api/v1/ranks/from-preset` — idempotent merge; returns the
  /// gym's full ladder afterwards.
  Future<List<RankFullResponse>> seedFromPreset(
    String gymId,
    String gymType,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/from-preset',
      data: {'gym_id': gymId, 'gym_type': gymType},
    );
    return _items(response.data);
  }

  /// `GET /api/v1/ranks/presets/grouped` — preset ladders keyed by
  /// gym type, each main rank with its sub-ranks nested.
  Future<Map<String, List<RankPresetGroup>>> listPresetsGrouped() async {
    final response = await _apiClient.get('/api/v1/ranks/presets/grouped');
    final presets =
        (response.data as Map<String, dynamic>)['presets']
            as Map<String, dynamic>;
    return presets.map(
      (gymType, groups) => MapEntry(
        gymType,
        (groups as List<dynamic>)
            .map((e) => RankPresetGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
  }

  /// `POST /api/v1/ranks/reorder` — applies a full new ordering
  /// atomically; returns the reordered ladder.
  Future<List<RankFullResponse>> reorderRanks(
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
    return _items(response.data);
  }

  // ----- Per-member rank changes -----

  /// `POST /api/v1/ranks/promote-member` — advance one rung; returns
  /// the member's new rank.
  Future<RankFullResponse> promoteMember(
    String gymId,
    String memberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/promote-member',
      data: {'gym_id': gymId, 'member_id': memberId},
    );
    return RankFullResponse.fromJson(
      (response.data as Map<String, dynamic>)['new_rank']
          as Map<String, dynamic>,
    );
  }

  /// `POST /api/v1/ranks/set-member-rank` — set an explicit rank (or
  /// `null` to unassign). Returns the new rank, or `null` when
  /// unassigned.
  Future<RankFullResponse?> setMemberRank(
    String gymId,
    String memberId,
    String? rankId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/ranks/set-member-rank',
      data: {'gym_id': gymId, 'member_id': memberId, 'rank_id': rankId},
    );
    final newRank = (response.data as Map<String, dynamic>)['new_rank'];
    return newRank == null
        ? null
        : RankFullResponse.fromJson(newRank as Map<String, dynamic>);
  }

  // ----- Group-level helpers (client fan-out) -----
  //
  // `gym_ranks.main_name` is denormalised per row, so a main-group
  // rename/delete spans rows. These fan out over the single-rank
  // endpoints. (A future atomic bulk-group endpoint could replace
  // them; see the rank ladder plan.)

  /// Rename every sub-rank in a main group by updating each row's
  /// `main_name`. Parallel is safe — these are independent field
  /// edits with no member-reassignment side effect.
  Future<void> renameMainGroup(
    List<String> rankIds,
    String newMainName,
  ) async {
    await Future.wait(
      rankIds.map(
        (id) => updateRank(id, RankUpdateData(mainName: newMainName)),
      ),
    );
  }

  /// Delete every sub-rank in a main group. Sequential, highest
  /// sub-order first, so members cascade down to the group's lower
  /// neighbour deterministically (each delete reassigns members).
  Future<void> deleteMainGroup(List<String> rankIdsHighestSubFirst) async {
    for (final id in rankIdsHighestSubFirst) {
      await deleteRank(id);
    }
  }

  List<RankFullResponse> _items(dynamic data) {
    final items = (data as Map<String, dynamic>)['items'] as List<dynamic>;
    return items
        .map((e) => RankFullResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
