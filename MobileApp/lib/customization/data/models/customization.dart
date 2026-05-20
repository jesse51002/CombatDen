import 'package:equatable/equatable.dart';

import 'package:mobile_app/customization/data/models/color_mode.dart';
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
  final ColorMode colorMode;
  final Map<String, CustomizationColor> colors;
  final Map<String, CustomizationImage> images;

  const Customization({
    required this.app,
    required this.displayName,
    required this.colorMode,
    required this.colors,
    required this.images,
  });

  factory Customization.fromJson(Map<String, dynamic> json) {
    // The wire envelope: `color_set.{mode,colors}` +
    // `image_set.images`. No legacy-shape fallback — a payload that
    // doesn't match the current contract yields empty maps, and the
    // app's existing bundled defaults (BrandColor / BrandImage) own
    // the fallback. `_parseMap` already null-guards a missing or
    // non-map section to `{}`.
    final colorSet = json['color_set'];
    final imageSet = json['image_set'];
    final colorsRaw = colorSet is Map ? colorSet['colors'] : null;
    final imagesRaw = imageSet is Map ? imageSet['images'] : null;
    final modeRaw = colorSet is Map ? colorSet['mode'] : null;
    return Customization(
      app: (json['app'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      colorMode: ColorMode.fromJson(modeRaw),
      colors: _parseMap(
        colorsRaw,
        CustomizationColor.fromJson,
      ),
      images: _parseMap(
        imagesRaw,
        CustomizationImage.fromJson,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'app': app,
        'display_name': displayName,
        'color_set': {
          'mode': colorMode.toJson(),
          'colors': {
            for (final e in colors.entries) e.key: e.value.toJson(),
          },
        },
        'image_set': {
          'images': {
            for (final e in images.entries) e.key: e.value.toJson(),
          },
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
  List<Object?> get props => [app, displayName, colorMode, colors, images];
}
