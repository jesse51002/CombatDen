import 'package:equatable/equatable.dart';

import 'package:theme_flutter/data/models/customization_style.dart';

/// One page of the paginated `GET /apps/{appId}/styles` envelope.
///
/// [items] is the slice; [total] is the post-filter match count
/// (the full list size for the active search query, not the catalog
/// size); [offset] and [limit] echo the request. Callers can derive
/// `hasMore = offset + items.length < total` without tracking what
/// they asked for.
class ThemeStylesPage extends Equatable {
  final List<ThemeStyle> items;
  final int total;
  final int offset;
  final int limit;

  const ThemeStylesPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  /// True when the next page would yield at least one more item.
  bool get hasMore => offset + items.length < total;

  /// Empty page (offset 0, limit 0) — useful as an initial state
  /// before the first fetch resolves.
  static const empty = ThemeStylesPage(
    items: <ThemeStyle>[],
    total: 0,
    offset: 0,
    limit: 0,
  );

  /// Builds from the wire envelope. Resilient like
  /// [ThemeStyle.fromJson]: missing / wrong-typed numeric
  /// fields degrade to 0; a missing `items` becomes an empty list.
  factory ThemeStylesPage.fromJson(
    Map<String, dynamic> json,
    String Function(String raw) resolveUrl,
  ) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (e) => ThemeStyle.fromJson(
                  Map<String, dynamic>.from(e),
                  resolveUrl,
                ),
              )
              .where((s) => s.id.isNotEmpty)
              .toList(growable: false)
        : const <ThemeStyle>[];
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    return ThemeStylesPage(
      items: items,
      total: asInt(json['total']),
      offset: asInt(json['offset']),
      limit: asInt(json['limit']),
    );
  }

  @override
  List<Object?> get props => [items, total, offset, limit];
}
