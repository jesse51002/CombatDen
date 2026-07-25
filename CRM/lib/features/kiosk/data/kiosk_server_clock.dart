import 'dart:async';
import 'dart:developer';

import 'package:intl/intl.dart';

import 'package:crm/core/network/api_client.dart';

/// Reads the backend's wall clock so the kiosk runway is anchored to SERVER
/// time instead of the device clock: the runway is an absolute deadline pinned
/// at entry and re-checked on every reload, so an iPad whose clock is rolled
/// BACK would otherwise read "still before the deadline" indefinitely and
/// extend the member surface past its true expiry. (A live session's timers are
/// duration-based, so the exposure only ever existed across a reload.)
///
/// It reads the `Date` header off a cheap, unauthenticated `GET /health`
/// through the shared [ApiClient]. On Flutter web the browser can only see that
/// header because the backend CORS config exposes it (`expose_headers=
/// ["Date"]`); without that, or offline, the read returns null and the caller
/// falls back / fails closed. One read at entry and one at restore is enough.
class KioskServerClock {
  KioskServerClock({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// The base URL has no `/api/v1` suffix, so `/health` resolves as a sibling
  /// of the versioned routes.
  static const String _timeProbePath = '/health';

  /// Upper bound on the probe so an offline kiosk boot fails closed quickly
  /// instead of hanging on the 30s [ApiClient] timeout.
  static const Duration _timeout = Duration(seconds: 5);

  /// RFC 7231 IMF-fixdate — always GMT, parsed as UTC. `en_US` is intl's
  /// built-in locale, so no `initializeDateFormatting` is needed.
  static final DateFormat _httpDate =
      DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');

  /// The server's current time (UTC), or null when it can't be read — offline,
  /// the header missing (CORS not exposing `Date`), or unparseable. Never
  /// throws; the caller decides how to fall back.
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
