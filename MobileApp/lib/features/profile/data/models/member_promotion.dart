import 'package:json_annotation/json_annotation.dart';

part 'member_promotion.g.dart';

/// The member's most recent rank change, when it was a PROMOTION — the payload
/// the belt-promotion card animates.
///
/// Mirrors `MemberPortalPromotion` in
/// `FastApiBackend/src/member_portal/schema/member_portal_schema.py`, carried
/// as the nullable `latest_promotion` on `MemberPortalProfile`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}`).
///
/// **Only a genuine promotion ever arrives.** The server nulls demotions,
/// lateral corrections and unassignments, so the card never has to hedge about
/// direction — and nothing here references a class, because promotions are
/// staff-driven from the ready-to-promote board minutes to days after one. The
/// copy reads "You've been promoted", never "that class promoted you".
///
/// Only the FROM side is genuinely optional: a first assignment has no leaf to
/// have come from, so it arrives with [oldRankName] and [oldImageUrl] null and
/// the card renders an arrival rather than an animation out of nothing.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberPromotion {
  /// The `member_activities` row this describes — THE watermark key. Compared
  /// by EQUALITY, never by ordering; see `promotion_rules.dart`.
  final String activityId;

  /// When the change was recorded, UTC. For display and ordering only — never
  /// the watermark, and this card does not display it.
  final DateTime promotedAt;

  /// The display name of the leaf the member came FROM (`Blue Belt` /
  /// `Blue Belt · 2 Stripes`). Null on a first assignment. It is ONE composed
  /// string — never split it on the `·`.
  final String? oldRankName;

  /// The display name of the leaf the member moved TO. Nullable for wire
  /// compatibility only; a promotion always has a TO leaf in practice.
  final String? newRankName;

  /// Belt art of the FROM leaf, snapshotted at the moment of the change (the
  /// source columns are user-writable, so a live lookup would let new belt art
  /// rewrite an old promotion). Null on a first assignment, on a leaf with no
  /// image, or on a row written before the payload carried images.
  final String? oldImageUrl;

  /// Belt art of the TO leaf, same snapshot rule.
  final String? newImageUrl;

  const MemberPromotion({
    required this.activityId,
    required this.promotedAt,
    this.oldRankName,
    this.newRankName,
    this.oldImageUrl,
    this.newImageUrl,
  });

  factory MemberPromotion.fromJson(Map<String, dynamic> json) =>
      _$MemberPromotionFromJson(json);

  /// A first assignment — staff giving a rank-less member their first belt, or
  /// the gym's lowest-rank backfill. There is nothing to animate FROM, so the
  /// card renders an arrival and names it "YOUR FIRST RANK" rather than a
  /// promotion out of nothing. Common at a new gym, not an edge case.
  bool get isFirstAssignment => oldRankName == null && oldImageUrl == null;

  /// True when the two sides would paint the same picture, so the
  /// cross-dissolve is a visual no-op and the swap beat has to be carried by
  /// the name exit, the swell and the sparkles alone.
  ///
  /// It covers both-empty (a legacy row with no images at all, where both
  /// sides resolve to the themed belt) and same-url (a stripe promotion with
  /// no per-sub override). Blank / whitespace-only is ABSENT, not broken — the
  /// rule `RankBeltImage` and `creatorAvatarProvider` already set.
  ///
  /// **No widget branches on this.** In every case the correct rendering is
  /// "resolve each side independently and dissolve"; the predicate exists so
  /// the degrade is testable and documented, not so a "legacy mode" can be
  /// added.
  bool get beltArtUnchanged =>
      (oldImageUrl?.trim() ?? '') == (newImageUrl?.trim() ?? '');
}
