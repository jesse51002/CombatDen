import 'dart:async';
import 'dart:developer';

import 'package:intl/intl.dart';

import 'package:crm/core/network/api_client.dart';

/// Reads the backend's wall clock so the kiosk runway can be anchored to
/// SERVER time instead of the device clock.
///
/// ## Why this exists (SEC-3)
/// The 12-hour kiosk runway is an absolute deadline pinned at entry and
/// re-checked on every reload. If that check trusts the device clock, a
/// supervised iPad whose clock is rolled **back** reads "still before the
/// deadline" indefinitely, extending the member surface past its true expiry.
/// The exposure is only across a reload — a live session's timers are duration
/// based (monotonic) and can't be moved by the clock. Anchoring entry AND the
/// restore check to the server's clock closes that hole.
///
/// ## How it reads the time
/// It issues a cheap, unauthenticated `GET /health` through the shared
/// [ApiClient] and reads the HTTP `Date` response header (RFC 7231
/// IMF-fixdate, always GMT). On Flutter web the browser can only see that
/// header because the backend CORS config exposes it (`expose_headers=
/// ["Date"]`); without that exposure, or offline, the read returns null and
/// the caller falls back / fails closed. One read at entry and one at restore
/// is enough — there is no continuous sync (1-second granularity is ample for
/// a 12-hour runway).
class KioskServerClock {
  KioskServerClock({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// A cheap, unauthenticated endpoint that carries a `Date` header like every
  /// origin-server response. Reachable at the API root (the base URL has no
  /// `/api/v1` suffix, so `/health` resolves as a sibling of the versioned
  /// routes).
  static const String _timeProbePath = '/health';

  /// Upper bound on the probe so an offline kiosk boot fails closed quickly
  /// instead of hanging on the 30s [ApiClient] timeout.
  static const Duration _timeout = Duration(seconds: 5);

  /// The HTTP `Date` header format (RFC 7231 IMF-fixdate) — always GMT, parsed
  /// as UTC. `en_US` is intl's built-in locale, so no `initializeDateFormatting`
  /// is needed.
  static final DateFormat _httpDate =
      DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');

  /// The server's current time (UTC), or null when it can't be read — offline,
  /// the header missing (CORS not exposing `Date`), or an unparseable value.
  /// Never throws; the caller decides how to fall back.
  Future<DateTime?> serverNow() async {
    try {
      final resp = await _api.get<dynamic>(_timeProbePath).timeout(_timeout);
      final header = resp.headers.value('date');
      if (header == null) return null;
      return _httpDate.parse(header, true); // interpret the GMT time as UTC
    } catch (e, s) {
      log('Kiosk server clock read failed', error: e, stackTrace: s);
      return null;
    }
  }
}
