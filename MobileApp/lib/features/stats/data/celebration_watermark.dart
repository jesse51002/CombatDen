import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-member store of the newest attended `occurred_at` the member has already
/// SEEN celebrated. Backed by shared_preferences under a PER-MEMBER key, so
/// switching profiles never replays another member's history.
///
/// The decision rule itself is the pure [decideCelebration] in
/// `celebration_rules.dart`; this class is only the storage seam. A
/// null/absent watermark means "no attendance seen yet" — the caller seeds it
/// silently. On a strictly-newer attendance the caller fires the flow, then
/// calls [mark] to advance the watermark.
class CelebrationWatermark {
  const CelebrationWatermark();

  static String keyFor(String memberId) => 'celebration_watermark_$memberId';

  /// The newest attended instant this member has seen, or null when no
  /// watermark exists yet (first run / reinstall / new member). Never throws.
  Future<DateTime?> lastSeen(String memberId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyFor(memberId));
      if (raw == null) return null;
      return DateTime.tryParse(raw);
    } catch (e, st) {
      log('CelebrationWatermark.lastSeen failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// Advance the watermark to [occurredAt] (stored ISO-8601). Never throws.
  Future<void> mark(String memberId, DateTime occurredAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyFor(memberId), occurredAt.toIso8601String());
    } catch (e, st) {
      log('CelebrationWatermark.mark failed', error: e, stackTrace: st);
    }
  }
}
