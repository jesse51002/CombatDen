import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-member store of the `activity_id` of the promotion the member has
/// already SEEN celebrated. Backed by shared_preferences under a PER-MEMBER
/// key, so switching profiles never replays another member's belt.
///
/// A straight port of [CelebrationWatermark] with a `String` id in place of a
/// `DateTime` — including its seed-silently-on-null rule, which is what makes
/// reinstall and second-device correct. The decision rule itself is the pure
/// [decidePromotion] in `promotion_rules.dart`; this class is only the storage
/// seam. Both methods swallow and log their failures rather than throwing: a
/// broken preference store must never take down the app open.
class PromotionWatermark {
  const PromotionWatermark();

  static String keyFor(String memberId) => 'promotion_watermark_$memberId';

  /// The `activity_id` this member has seen celebrated, or null when no
  /// watermark exists yet (first run / reinstall / new member). Never throws.
  Future<String?> lastSeen(String memberId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyFor(memberId));
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } catch (e, st) {
      log('PromotionWatermark.lastSeen failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// Advance the watermark to [activityId]. Never throws.
  Future<void> mark(String memberId, String activityId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyFor(memberId), activityId);
    } catch (e, st) {
      log('PromotionWatermark.mark failed', error: e, stackTrace: st);
    }
  }
}
