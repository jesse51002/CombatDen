import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

/// Accumulates a paged + searchable view of `ThemeRuntime.fetchStylesPage`.
///
/// Owns the user-facing list state for a picker UI: the items loaded so
/// far across pages, the current search query, whether a fetch is in
/// flight, and whether the next page would yield more. Changing the
/// query resets the accumulated items and refetches from offset 0 with
/// a short debounce so a fast typist doesn't trigger a request per
/// keystroke. UI listens via the [ChangeNotifier] surface; widgets
/// rebuild on every state transition.
///
/// Failures degrade quietly (the items stay, [errored] flips true) so a
/// flaky service doesn't blow up the picker mid-scroll.
class StylesPager extends ChangeNotifier {
  StylesPager({this.pageSize = 20, Duration? searchDebounce})
    : _searchDebounce =
          searchDebounce ?? const Duration(milliseconds: 250) {
    _loadFirstPage();
  }

  /// How many styles to request per page.
  final int pageSize;
  final Duration _searchDebounce;

  final List<ThemeStyle> _items = [];

  /// All styles loaded across pages for the active [query].
  List<ThemeStyle> get items => List.unmodifiable(_items);

  /// Post-filter total count for the active [query]. ``0`` before the
  /// first response.
  int get total => _total;
  int _total = 0;

  /// Current search query. Empty string == no filter.
  String get query => _query;
  String _query = '';

  /// True while a fetch is in flight.
  bool get isLoading => _isLoading;
  bool _isLoading = false;

  /// True when the latest fetch failed. Cleared on the next successful
  /// fetch.
  bool get errored => _errored;
  bool _errored = false;

  /// True when at least one more page exists for the active query.
  bool get hasMore => _items.length < _total;

  /// True when the first page has not yet been requested for the
  /// current query — distinct from "loaded zero items" for empty
  /// states.
  bool get hasLoadedFirstPage => _hasLoadedFirstPage;
  bool _hasLoadedFirstPage = false;

  // Identifies the active query "generation". When the query changes,
  // any in-flight response from the previous generation is discarded —
  // protects against out-of-order responses overwriting fresh results.
  int _queryGeneration = 0;
  Timer? _debounce;

  /// Update the search query. Resets the accumulated items and
  /// schedules a debounced refetch from offset 0.
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

  /// Fetch the next page if one exists and no fetch is already in
  /// flight.
  Future<void> loadMore() async {
    if (_isLoading) return;
    if (_hasLoadedFirstPage && !hasMore) return;
    final generation = _queryGeneration;
    _isLoading = true;
    _errored = false;
    notifyListeners();
    try {
      final page = await ThemeRuntime.fetchStylesPage(
        offset: _items.length,
        limit: pageSize,
        query: _query.isEmpty ? null : _query,
      );
      // Stale response from a superseded query — drop it.
      if (generation != _queryGeneration) return;
      _items.addAll(page.items);
      _total = page.total;
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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
