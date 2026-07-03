import 'package:equatable/equatable.dart';

import 'package:crm/features/rewards/data/models/pending_redemption_item.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';

enum RewardsCatalogStatus { initial, loading, loaded, error }
enum RewardsPendingStatus { initial, loading, loaded, error }

/// State for the rewards feature.
///
/// Holds the catalog list, the pending redemption queue, and mutation
/// tracking for the form dialogs.
///
/// Dialogs detect success via monotonic tokens:
/// - [catalogSuccessToken] bumps on every successful catalog mutation
///   (create / update / delete).
/// - [pendingSuccessToken] bumps on every successful redemption action
///   (approve / reject).
class RewardsState extends Equatable {
  // ── Catalog ──
  final RewardsCatalogStatus catalogStatus;
  final List<RewardResponse> rewards;
  final String? catalogError;

  // ── Pending queue ──
  final RewardsPendingStatus pendingStatus;
  final List<PendingRedemptionItem> pendingItems;
  final String? pendingError;

  // ── Mutation ──
  /// True while a create/update/delete/approve/reject call is in flight.
  final bool isMutating;
  final String? mutationError;

  /// Bumped on every successful catalog mutation (create/update/delete).
  final int catalogSuccessToken;

  /// Bumped on every successful redemption action (approve/reject).
  final int pendingSuccessToken;

  /// Set when an approve/reject returns 409 (already decided externally).
  /// Cleared by [RewardsErrorCleared].
  final bool redemptionAlreadyDecided;

  const RewardsState({
    this.catalogStatus = RewardsCatalogStatus.initial,
    this.rewards = const [],
    this.catalogError,
    this.pendingStatus = RewardsPendingStatus.initial,
    this.pendingItems = const [],
    this.pendingError,
    this.isMutating = false,
    this.mutationError,
    this.catalogSuccessToken = 0,
    this.pendingSuccessToken = 0,
    this.redemptionAlreadyDecided = false,
  });

  RewardsState copyWith({
    RewardsCatalogStatus? catalogStatus,
    List<RewardResponse>? rewards,
    String? catalogError,
    bool clearCatalogError = false,
    RewardsPendingStatus? pendingStatus,
    List<PendingRedemptionItem>? pendingItems,
    String? pendingError,
    bool clearPendingError = false,
    bool? isMutating,
    String? mutationError,
    bool clearMutationError = false,
    int? catalogSuccessToken,
    int? pendingSuccessToken,
    bool? redemptionAlreadyDecided,
  }) => RewardsState(
    catalogStatus: catalogStatus ?? this.catalogStatus,
    rewards: rewards ?? this.rewards,
    catalogError: clearCatalogError ? null : catalogError ?? this.catalogError,
    pendingStatus: pendingStatus ?? this.pendingStatus,
    pendingItems: pendingItems ?? this.pendingItems,
    pendingError: clearPendingError ? null : pendingError ?? this.pendingError,
    isMutating: isMutating ?? this.isMutating,
    mutationError:
        clearMutationError ? null : mutationError ?? this.mutationError,
    catalogSuccessToken: catalogSuccessToken ?? this.catalogSuccessToken,
    pendingSuccessToken: pendingSuccessToken ?? this.pendingSuccessToken,
    redemptionAlreadyDecided:
        redemptionAlreadyDecided ?? this.redemptionAlreadyDecided,
  );

  @override
  List<Object?> get props => [
    catalogStatus,
    rewards,
    catalogError,
    pendingStatus,
    pendingItems,
    pendingError,
    isMutating,
    mutationError,
    catalogSuccessToken,
    pendingSuccessToken,
    redemptionAlreadyDecided,
  ];
}
