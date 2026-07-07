import 'package:equatable/equatable.dart';

/// One selectable style returned by the ThemeService's
/// `GET /apps/{appId}/styles` endpoint. App-agnostic: just the run
/// [id] to switch to, the human [displayName] to show, an absolute
/// [celebrationImageUrl] for the card art, and the [category]
/// classification bucket (the app-declared vocabulary, e.g.
/// `Fighting`, `Yoga`, `Pilates`, `Barre`, `HIIT`, `Cardio`, `Dance`,
/// `Wellness` for CombatDen) used to filter the style picker.
///
/// Parsing is resilient (mirrors [ThemeConfig.fromJson]): missing
/// fields degrade to empty strings / null rather than throwing.
class ThemeStyle extends Equatable {
  final String id;
  final String displayName;
  final String celebrationImageUrl;
  final String? category;

  /// The VideoService gym id this style belongs to, when the catalog is the
  /// gym browser (AppManagement). The content key — the host stores it on
  /// selection and fetches the gym's detail/feed by it. Null for plain
  /// ThemeService styles, which have no gym.
  final String? gymId;

  const ThemeStyle({
    required this.id,
    required this.displayName,
    required this.celebrationImageUrl,
    this.category,
    this.gymId,
  });

  /// Builds from one wire item. [resolveUrl] absolutises the
  /// relative `celebration_image` path the API ships (same
  /// convention as the image slots in [ThemeConfig]).
  factory ThemeStyle.fromJson(
    Map<String, dynamic> json,
    String Function(String raw) resolveUrl,
  ) {
    final raw = (json['celebration_image'] as String?) ?? '';
    return ThemeStyle(
      id: (json['id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      celebrationImageUrl: raw.isEmpty ? '' : resolveUrl(raw),
      category: json['category'] as String?,
      gymId: json['gym_id'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        displayName,
        celebrationImageUrl,
        category,
        gymId,
      ];
}
