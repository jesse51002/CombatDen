import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  void setQuery(String next) {
    final trimmed = next.trim();
    if (trimmed == _query) return;
    _query = trimmed;
    _queryGeneration++;
    _items.clear();
    _total = 0;
    _errored = false;
    _hasLoadedFirstPage = false;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, _loadFirstPage);
  }

  Future<void> loadMore() async {
    if (_isLoading) return;
    if (_hasLoadedFirstPage && !hasMore) return;
    final generation = _queryGeneration;
    _isLoading = true;
    _errored = false;
    notifyListeners();
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
          .timeout(const Duration(seconds: 5));
      if (generation != _queryGeneration) return;
      if (response.statusCode != 200) {
        throw Exception('gyms fetch failed (${response.statusCode})');
      }
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
        notifyListeners();
      }
    }
  }

  Future<void> _loadFirstPage() => loadMore();

  ThemeStyle _toStyle(Map<String, dynamic> gym) {
    final raw = (gym['celebration_image_url'] as String?) ?? '';
    return ThemeStyle(
      id: (gym['theme'] as String?) ?? '',
      displayName: _titleize((gym['gym_id'] as String?) ?? ''),
      celebrationImageUrl: raw.isEmpty ? '' : _resolve(raw),
      // The coarse parent bucket (Fighting/Yoga/…) is what the picker filters by.
      gymType: gym['parent_gym_type'] as String?,
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
    _debounce?.cancel();
    super.dispose();
  }
}
