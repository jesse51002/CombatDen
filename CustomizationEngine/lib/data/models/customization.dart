import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'package:customization_engine/data/models/color_mode.dart';
import 'package:customization_engine/data/models/customization_color.dart';
import 'package:customization_engine/data/models/lottie_override.dart';

/// A loaded, resolved customization. App-agnostic: colours,
/// images, fonts and texts are typed-value maps keyed by slot id
/// — the engine never knows which slots a given app expects
/// (that's the caller's expected-key lists). Parsing is
/// resilient: a missing/non-map section is `{}` and a single
/// malformed slot is skipped, never failing the whole payload.
class Customization extends Equatable {
  final String app;
  final String displayName;
  final ColorMode colorMode;
  final Map<String, CustomizationColor> colors;

  /// The wire's flat recommendation palette: every `<slot>_<derivation>`
  /// pair (e.g. `primary_dark`, `background_popup`) plus shared
  /// surface tokens (`card`, `popup`, `divider`). Single source of
  /// truth for `DesignConstants`'s derived colour tokens.
  final Map<String, Color> palette;

  /// Slot -> fetch URL. The wire ships this flat (no wrapper, no
  /// prompt) — just the URL the client uses to GET the PNG.
  final Map<String, String> images;

  /// Slot -> Google Fonts family. Flat on the wire — categories,
  /// prose, and per-slot delivery URLs are dropped at the API
  /// layer because Flutter only needs the family to call
  /// `GoogleFonts.getFont(...)`.
  final Map<String, String> fonts;

  /// Brand-rewritten copy strings, keyed by slot id (e.g.
  /// `class_booked_headline` → "You're in"). Absent slots fall
  /// back to whatever the call site declares as its default.
  final Map<String, String> texts;

  /// Slot -> SVG fetch URL. Flat on the wire, exactly like [images]
  /// (icons are monochrome SVGs the app tints per theme). Absent
  /// slots fall back to the call site's `Symbols.*_sharp`.
  final Map<String, String> icons;

  /// Slot -> lottie override (preset URL + region→role recolour map).
  /// Absent slots fall back to the call site's bundled `.json`.
  final Map<String, LottieOverride> lotties;

  const Customization({
    required this.app,
    required this.displayName,
    required this.colorMode,
    required this.colors,
    required this.palette,
    required this.images,
    required this.fonts,
    required this.texts,
    required this.icons,
    required this.lotties,
  });

  factory Customization.fromJson(Map<String, dynamic> json) {
    // Wire envelope: `color_set.{mode, colors, palette}` (typed,
    // passthrough), `text_set.texts` (typed, passthrough), and
    // flat `images` / `fonts` maps at the top level. Each missing
    // section is `{}` (handled by the helper parsers).
    final colorSet = json['color_set'];
    final textSet = json['text_set'];
    final colorsRaw = colorSet is Map ? colorSet['colors'] : null;
    final paletteRaw = colorSet is Map ? colorSet['palette'] : null;
    final modeRaw = colorSet is Map ? colorSet['mode'] : null;
    final textsRaw = textSet is Map ? textSet['texts'] : null;
    return Customization(
      app: (json['app'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      colorMode: ColorMode.fromJson(modeRaw),
      colors: _parseMap(colorsRaw, CustomizationColor.fromJson),
      palette: _parsePalette(paletteRaw),
      images: _parseStringMap(json['images']),
      fonts: _parseStringMap(json['fonts']),
      texts: _parseTexts(textsRaw),
      icons: _parseStringMap(json['icons']),
      lotties: _parseMap(json['lotties'], LottieOverride.fromJson),
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
    'images': Map<String, String>.from(images),
    'fonts': Map<String, String>.from(fonts),
    'text_set': {
      'texts': {
        for (final e in texts.entries) e.key: {'value': e.value},
      },
    },
    'icons': Map<String, String>.from(icons),
    'lotties': {
      for (final e in lotties.entries) e.key: e.value.toJson(),
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

  static Map<String, String> _parseStringMap(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key is! String || value is! String) return;
      if (value.isEmpty) return;
      result[key] = value;
    });
    return result;
  }

  static Map<String, Color> _parsePalette(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, Color>{};
    raw.forEach((key, value) {
      if (key is! String) return;
      final color = CustomizationColor.parseColorValue(value);
      if (color != null) result[key] = color;
    });
    return result;
  }

  static Map<String, String> _parseTexts(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final v = value['value'];
      if (v is String && v.isNotEmpty) {
        result[key] = v;
      }
    });
    return result;
  }

  @override
  List<Object?> get props => [
    app,
    displayName,
    colorMode,
    colors,
    palette,
    images,
    fonts,
    texts,
    icons,
    lotties,
  ];
}
