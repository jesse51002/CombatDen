import 'package:equatable/equatable.dart';

import 'package:mobile_app/customization/data/models/customization_color.dart';
import 'package:mobile_app/customization/data/models/customization_image.dart';

/// A loaded, resolved customization. App-agnostic: colours and
/// images are typed-value maps keyed by slot id — the engine
/// never knows which slots a given app expects (that's the
/// caller's expected-key lists). Parsing is resilient: a
/// missing/non-map section is `{}` and a single malformed slot
/// is skipped, never failing the whole payload.
class Customization extends Equatable {
  final String app;
  final String displayName;
  final Map<String, CustomizationColor> colors;
  final Map<String, CustomizationImage> images;

  const Customization({
    required this.app,
    required this.displayName,
    required this.colors,
    required this.images,
  });

  factory Customization.fromJson(Map<String, dynamic> json) {
    return Customization(
      app: (json['app'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      colors: _parseMap(
        json['colors'],
        CustomizationColor.fromJson,
      ),
      images: _parseMap(
        json['images'],
        CustomizationImage.fromJson,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'app': app,
        'display_name': displayName,
        'colors': {
          for (final e in colors.entries) e.key: e.value.toJson(),
        },
        'images': {
          for (final e in images.entries) e.key: e.value.toJson(),
        },
      };

  static Map<String, T> _parseMap<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! Map) return <String, T>{};
    final result = <String, T>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      try {
        result[key] = fromJson(
          Map<String, dynamic>.from(value),
        );
      } catch (_) {
        // Skip a malformed slot; keep the rest.
      }
    });
    return result;
  }

  @override
  List<Object?> get props => [app, displayName, colors, images];
}
