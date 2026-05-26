import 'package:equatable/equatable.dart';

/// One selectable style returned by the CustomizationService's
/// `GET /apps/{appId}/styles` endpoint. App-agnostic: just the run
/// [id] to switch to, the human [displayName] to show, and an
/// absolute [celebrationImageUrl] for the card art.
///
/// Parsing is resilient (mirrors [Customization.fromJson]): missing
/// fields degrade to empty strings rather than throwing.
class CustomizationStyle extends Equatable {
  final String id;
  final String displayName;
  final String celebrationImageUrl;

  const CustomizationStyle({
    required this.id,
    required this.displayName,
    required this.celebrationImageUrl,
  });

  /// Builds from one wire item. [resolveUrl] absolutises the
  /// relative `celebration_image` path the API ships (same
  /// convention as the image slots in [Customization]).
  factory CustomizationStyle.fromJson(
    Map<String, dynamic> json,
    String Function(String raw) resolveUrl,
  ) {
    final raw = (json['celebration_image'] as String?) ?? '';
    return CustomizationStyle(
      id: (json['id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      celebrationImageUrl: raw.isEmpty ? '' : resolveUrl(raw),
    );
  }

  @override
  List<Object?> get props => [id, displayName, celebrationImageUrl];
}
