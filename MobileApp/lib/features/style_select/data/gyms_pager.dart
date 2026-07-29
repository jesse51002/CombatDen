import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

import 'package:mobile_app/core/video_service_config.dart';

/// Base URL of the ThemeService output API, used ONLY to absolutise a gym
/// card's celebration image (a ThemeService-relative path). Mirrors the
/// `theme_flutter` engine's default; override with `--dart-define=CUST_BASE_URL`.
const String _kThemeServiceBaseUrl = String.fromEnvironment(
  'CUST_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Accumulates a paged + searchable view of the VideoService **gym browser**
/// (`GET /presets/templates`), mapping each gym to a [ThemeStyle] the existing
/// style picker renders — `id` is the gym's **theme** (so tapping it loads that
/// theme), the card art is the gym's celebration image. Gyms are the entry
/// point; the theme lives on the gym.
///
/// Same public surface as the engine's `StylesPager` (items / query / loadMore
/// / isLoading / hasMore / errored), so it is a drop-in for the picker. Kept
/// app-side on purpose: the engine must never know about the VideoService.
class GymsPager extends ChangeNotifier {
  GymsPager({this.pageSize = 20, Duration? searchDebounce})
    : _searchDebounce = searchDebounce ?? const Duration(milliseconds: 250) {
    _dio = Dio(
      BaseOptions(
        baseUrl: kVideoBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'Accept': 'application/json'},
      ),
    );
    _loadFirstPage();
  }

  final int pageSize;
  final Duration _searchDebounce;
  late final Dio _dio;

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
      final response = await _dio.get<dynamic>(
        '/presets/templates',
        queryParameters: {
          'offset': _items.length,
          'limit': pageSize,
          if (_query.isNotEmpty) 'query': _query,
        },
      );
      if (generation != _queryGeneration) return;
      final data = response.data;
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

  /// One gym card -> a [ThemeStyle]: `id` is the gym's theme (loaded on tap),
  /// the celebration image is absolutised against the ThemeService base.
  ThemeStyle _toStyle(Map<String, dynamic> gym) {
    final raw = (gym['celebration_image_url'] as String?) ?? '';
    return ThemeStyle(
      id: (gym['theme'] as String?) ?? '',
      displayName: _titleize((gym['video_gym_id'] as String?) ?? ''),
      celebrationImageUrl: raw.isEmpty ? '' : _resolve(raw),
      // The coarse parent bucket (Fighting/Yoga/…) is what the picker filters by.
      category: gym['parent_gym_type'] as String?,
      // The content key: stored on selection so videos / classes / rewards
      // fetch this gym's content, not just re-brand.
      gymId: gym['video_gym_id'] as String?,
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
