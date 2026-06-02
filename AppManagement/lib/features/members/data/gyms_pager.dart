import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

/// VideoService base (the gym browser lives there); mirrors the video carve-out.
const String _kVideoBaseUrl = String.fromEnvironment(
  'VIDEO_BASE_URL',
  defaultValue: 'http://localhost:8002',
);
/// ThemeService base, used ONLY to absolutise a gym card's celebration image
/// (a ThemeService-relative path). Mirrors the engine default.
const String _kThemeServiceBaseUrl = String.fromEnvironment(
  'CUST_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Accumulates a paged + searchable view of the VideoService **gym browser**
/// (`GET /gyms`), mapping each gym to a [ThemeStyle] the existing
/// theme picker renders — `id` is the gym's **theme** (so tapping it loads that
/// theme via `ThemeRuntime.selectDesign`), the card art is the gym's celebration
/// image. Gyms are the entry point; the theme lives on the gym.
///
/// Same public surface as the engine's `StylesPager`, so it is a drop-in for the
/// picker. Kept app-side on purpose: the engine must never know the VideoService.
class GymsPager extends ChangeNotifier {
  GymsPager({this.pageSize = 20, Duration? searchDebounce})
    : _searchDebounce = searchDebounce ?? const Duration(milliseconds: 250) {
    _loadFirstPage();
  }

  final int pageSize;
  final Duration _searchDebounce;

  final List<ThemeStyle> _items = [];
  List<ThemeStyle> get items => List.unmodifiable(_items);

  int get total => _total;
  int _total = 0;

  String get query => _query;
  String _query = '';

  bool get isLoading => _isLoading;
  bool _isLoading = false;

  bool get errored => _errored;
  bool _errored = false;

  bool get hasMore => _items.length < _total;

  bool get hasLoadedFirstPage => _hasLoadedFirstPage;
  bool _hasLoadedFirstPage = false;

  int _queryGeneration = 0;
  Timer? _debounce;

  // An in-flight loadMore() resumes after its await even if the picker was
  // closed mid-fetch; notifying a disposed ChangeNotifier throws. Guard every
  // notify behind this so a late continuation degrades to a no-op.
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // Design id -> the theme's celebration-image URL carrying its content-hash
  // `?v=` token (from the ThemeService styles catalog), so a card's art
  // refreshes when the image is regenerated instead of sitting on the browser's
  // day-long cache. Fetched once; the VideoService-derived bare URL is the
  // fallback when the styles catalog is unreachable. ThemeService is reached
  // through the engine (dio), never `http` (VideoService-only).
  Map<String, String>? _celebrationByDesign;
  Future<void>? _celebrationFetch;

  Future<void> _ensureCelebrationUrls() =>
      _celebrationFetch ??= _fetchCelebrationUrls();

  Future<void> _fetchCelebrationUrls() async {
    final map = <String, String>{};
    try {
      const pageSize = 100;
      var offset = 0;
      while (true) {
        final page = await ThemeRuntime.fetchStylesPage(
          offset: offset,
          limit: pageSize,
        );
        for (final s in page.items) {
          if (s.celebrationImageUrl.isNotEmpty) {
            map[s.id] = s.celebrationImageUrl;
          }
        }
        offset += page.items.length;
        if (page.items.isEmpty || offset >= page.total) break;
      }
    } catch (_) {
      // Degrade quietly: fall back to the bare VideoService-derived URLs.
    }
    _celebrationByDesign = map;
  }

  void setQuery(String next) {
    final trimmed = next.trim();
    if (trimmed == _query) return;
    _query = trimmed;
    _queryGeneration++;
    _items.clear();
    _total = 0;
    _errored = false;
    _hasLoadedFirstPage = false;
    _safeNotify();
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, _loadFirstPage);
  }

  Future<void> loadMore() async {
    if (_isLoading) return;
    if (_hasLoadedFirstPage && !hasMore) return;
    final generation = _queryGeneration;
    _isLoading = true;
    _errored = false;
    _safeNotify();
    try {
      final uri = Uri.parse('$_kVideoBaseUrl/gyms').replace(
        queryParameters: {
          'offset': '${_items.length}',
          'limit': '$pageSize',
          if (_query.isNotEmpty) 'query': _query,
        },
      );
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (generation != _queryGeneration) return;
      if (response.statusCode != 200) {
        throw Exception('gyms fetch failed (${response.statusCode})');
      }
      // Load the tokened celebration URLs (once) so each card's art carries its
      // content-hash `?v=` and refreshes when the theme is regenerated.
      // Best-effort: on failure the bare VideoService URL is used.
      await _ensureCelebrationUrls();
      if (generation != _queryGeneration) return;
      final data = jsonDecode(response.body);
      final rawGyms = data is Map ? data['gyms'] : null;
      final styles = rawGyms is List
          ? rawGyms
                .whereType<Map>()
                .map((e) => _toStyle(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const <ThemeStyle>[];
      _items.addAll(styles);
      _total = (data is Map && data['total'] is int)
          ? data['total'] as int
          : _items.length;
      _hasLoadedFirstPage = true;
    } catch (_) {
      if (generation != _queryGeneration) return;
      _errored = true;
    } finally {
      if (generation == _queryGeneration) {
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> _loadFirstPage() => loadMore();

  ThemeStyle _toStyle(Map<String, dynamic> gym) {
    final theme = (gym['theme'] as String?) ?? '';
    final raw = (gym['celebration_image_url'] as String?) ?? '';
    return ThemeStyle(
      id: theme,
      displayName: _titleize((gym['gym_id'] as String?) ?? ''),
      // Prefer the ThemeService styles catalog's celebration URL — it carries
      // the content-hash `?v=` token so the card refreshes when the image is
      // regenerated; fall back to the bare VideoService-derived URL.
      celebrationImageUrl:
          _celebrationByDesign?[theme] ?? (raw.isEmpty ? '' : _resolve(raw)),
      // The coarse parent bucket (Fighting/Yoga/…) is what the picker filters by.
      gymType: gym['parent_gym_type'] as String?,
      // The content key: stored on selection so the loyalty/videos/preview
      // surfaces fetch this gym's detail + feed by it.
      gymId: gym['gym_id'] as String?,
    );
  }

  String _resolve(String raw) =>
      (raw.startsWith('http://') || raw.startsWith('https://'))
      ? raw
      : '$_kThemeServiceBaseUrl${raw.startsWith('/') ? '' : '/'}$raw';

  static String _titleize(String gymId) => gymId
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
