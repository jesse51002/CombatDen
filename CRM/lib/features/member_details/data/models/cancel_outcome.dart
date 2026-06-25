/// Result of a cancel-memberships request.
///
/// Describes which item_ids were successfully cancelled
/// and which failed. Built by [MemberRepository.cancelMemberships]
/// from the backend response:
///
/// - HTTP 200: all requested item_ids succeeded (parsed
///   from `cancel_dates` keys).
/// - HTTP 207 partial: the router returns a structured
///   `detail` (`{succeeded_item_ids, failed_item_ids}`); the
///   real split is parsed from it. A full Stripe error (no
///   structured detail, HTTP 500) falls back to all-failed.
/// - Other error: all requested item_ids failed.
class CancelOutcome {
  /// The item_ids that were successfully cancelled.
  final List<String> succeededItemIds;

  /// The item_ids that failed to cancel.
  final List<String> failedItemIds;

  const CancelOutcome({
    required this.succeededItemIds,
    required this.failedItemIds,
  });

  /// All requested items succeeded.
  bool get isFullSuccess => failedItemIds.isEmpty;

  /// Some items succeeded and some failed.
  bool get isPartial =>
      succeededItemIds.isNotEmpty && failedItemIds.isNotEmpty;

  /// All requested items failed.
  bool get isAllFailed => succeededItemIds.isEmpty;
}
