import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:crm/showcase/showcase_content.dart';

/// The public, category-keyed demo showcase content served by the backend
/// (`GET /api/v1/theme/showcase-defaults`) — one bucket of demo class + reward
/// cards per showcase category (Fighting/Yoga/…). It backs the phone preview's
/// demo content when there's no real gym showcase to draw from (always in the
/// public theme browser, and as a fallback in the admin preview).
///
/// This is a **public** endpoint (static demo content, no gym/member data), so
/// it rides `package:http` unauthenticated — the same public/template edge as
/// `VideoApiClient` — not the authed `ApiClient`. Fetched once and cached app-
/// side via [loadShowcaseDefaults]; a fetch failure degrades to the bundled
/// `kShowcaseClassesByGroup` / `kShowcaseRewardsByGroup` constants at the call
/// site (this returns an empty map, so `forCategory` yields null).

/// One category's demo class + reward cards, already mapped to the showcase's
/// own view models.
class ShowcaseGroupContent {
  const ShowcaseGroupContent({required this.classes, required this.rewards});

  final List<ShowcaseClassInfo> classes;
  final List<ShowcaseReward> rewards;
}

/// The whole category-keyed demo content payload.
class ShowcaseDefaults {
  const ShowcaseDefaults({required this.byCategory});

  /// Keyed by the wire category string (`Fighting`, `Yoga`, …).
  final Map<String, ShowcaseGroupContent> byCategory;

  /// The demo content for [category], or null when it's absent (or [category]
  /// is null) — the caller then falls back to the bundled offline constants.
  ShowcaseGroupContent? forCategory(String? category) =>
      category == null ? null : byCategory[category];

  factory ShowcaseDefaults.fromJson(Map<String, dynamic> json) {
    final raw = json['categories'];
    if (raw is! Map) return const ShowcaseDefaults(byCategory: {});
    final out = <String, ShowcaseGroupContent>{};
    raw.forEach((key, value) {
      if (key is String && value is Map) {
        out[key] = _groupFromJson(Map<String, dynamic>.from(value));
      }
    });
    return ShowcaseDefaults(byCategory: out);
  }

  static ShowcaseGroupContent _groupFromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) build) =>
        raw is List
        ? raw
              .whereType<Map>()
              .map((e) => build(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const [];
    return ShowcaseGroupContent(
      classes: list(json['classes'], _classFromJson),
      rewards: list(json['rewards'], _rewardFromJson),
    );
  }

  static ShowcaseClassInfo _classFromJson(Map<String, dynamic> json) =>
      ShowcaseClassInfo(
        name: (json['name'] as String?) ?? '',
        imageUrl: (json['image_url'] as String?) ?? '',
        instructorName: (json['instructor_name'] as String?) ?? '',
      );

  static ShowcaseReward _rewardFromJson(Map<String, dynamic> json) =>
      ShowcaseReward(
        title: (json['title'] as String?) ?? '',
        imageUrl: (json['image_url'] as String?) ?? '',
        priceLabel: (json['price_label'] as String?) ?? '',
        pointsCost: (json['points_cost'] as int?) ?? 0,
      );
}

/// Read-only client for the public showcase-defaults endpoint. Base URL:
/// override with `--dart-define=BACKEND_BASE_URL=http://<host>:8000`.
class ShowcaseDefaultsClient {
  ShowcaseDefaultsClient({String? baseUrl})
    : baseUrl = baseUrl ?? _kDefaultBaseUrl;

  final String baseUrl;

  static const String _kDefaultBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// `GET /api/v1/theme/showcase-defaults` — the category-keyed demo cards.
  /// Throws on failure so the memoized loader can decide to retry later.
  Future<ShowcaseDefaults> fetch() async {
    final uri = Uri.parse('$baseUrl/api/v1/theme/showcase-defaults');
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('showcase-defaults fetch failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is Map) {
      return ShowcaseDefaults.fromJson(Map<String, dynamic>.from(data));
    }
    throw Exception('showcase-defaults response was not an object');
  }
}

// App-side cache: the demo content is static, so fetch it once per session and
// share the future across every preview rebuild / re-mount.
Future<ShowcaseDefaults>? _cached;

/// The cached, app-side demo showcase content. Never throws — a fetch failure
/// resolves to an empty [ShowcaseDefaults] (so callers use the bundled offline
/// fallback) and clears the memo so a later call retries rather than pinning
/// the empty result for the whole session.
Future<ShowcaseDefaults> loadShowcaseDefaults() => _cached ??= _fetch();

Future<ShowcaseDefaults> _fetch() async {
  try {
    return await ShowcaseDefaultsClient().fetch();
  } catch (_) {
    _cached = null; // let the next call re-attempt.
    return const ShowcaseDefaults(byCategory: {});
  }
}
