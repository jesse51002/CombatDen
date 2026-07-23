import 'package:shared_preferences/shared_preferences.dart';

/// Persists the kiosk runway across page reloads so a mid-shift refresh (or a
/// crash) resumes the same locked surface instead of dropping into the admin
/// workspace.
///
/// It writes to `shared_preferences`, which on Flutter web is **the same
/// browser localStorage** that holds the Supabase session — a deliberate
/// *fate-share*: if that storage is wiped the session goes too, so a stray
/// kiosk flag can never outlive its session. The flag is only ever *honored*
/// inside the authenticated subtree (see `auth_gate.dart`), so a flag without
/// a session is inert and fails closed to the login screen.
///
/// Two keys: [_activeKey] (are we in kiosk?) and [_deadlineKey] (the absolute
/// end of the 12-hour runway, epoch-ms UTC). Injectable via [prefs] so the
/// cubit tests mock it.
class KioskSessionStore {
  static const String _activeKey = 'kiosk_active';
  static const String _deadlineKey = 'kiosk_deadline';

  final Future<SharedPreferences> _prefs;

  KioskSessionStore({Future<SharedPreferences>? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance();

  /// Mark kiosk active and pin the absolute runway [deadline] (stored as epoch
  /// milliseconds in UTC so it is timezone-stable across a reload).
  Future<void> save(DateTime deadline) async {
    final prefs = await _prefs;
    await prefs.setBool(_activeKey, true);
    await prefs.setInt(
      _deadlineKey,
      deadline.toUtc().millisecondsSinceEpoch,
    );
  }

  /// Read the persisted kiosk flag and deadline. Returns `(false, null)` when
  /// nothing is stored. The deadline comes back as a UTC [DateTime]; instant
  /// comparisons (`isBefore`) are timezone-agnostic so the caller compares it
  /// against a local `now` directly.
  Future<(bool active, DateTime? deadline)> read() async {
    final prefs = await _prefs;
    final active = prefs.getBool(_activeKey) ?? false;
    final ms = prefs.getInt(_deadlineKey);
    final deadline = ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return (active, deadline);
  }

  /// Wipe the kiosk flag + deadline. Called only after a sign-out is confirmed
  /// (the session is actually gone), never before — clearing early could strand
  /// the iPad in the admin workspace on the next boot.
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_activeKey);
    await prefs.remove(_deadlineKey);
  }
}
