import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// One resolved brand colour. App-agnostic leaf type.
///
/// The service ships every colour in four formats (oklch / hsl / rgb /
/// hex). We read [rgb] directly — the service has already done the
/// OKLCH→sRGB conversion — and expose a parsed [Color], plus six
/// deterministic derivation slots (`second` / `third` / `card` /
/// `popup` / `dark` / `light`) the service also pre-computes.
class CustomizationColor extends Equatable {
  /// Parsed sRGB colour from the wire's `rgb` block, or `null` when
  /// the block is missing/unparseable. Call sites fall back to their
  /// bundled default.
  final Color? color;

  /// Six pre-computed variants keyed by derivation id (`second`,
  /// `third`, `card`, `popup`, `dark`, `light`). Each is `null` only
  /// when its `rgb` block was missing/unparseable.
  final Map<String, Color> derivations;

  /// Human label, e.g. "Sunshine Duck Yellow".
  final String displayName;

  /// Purpose/usage prose for the colour.
  final String description;

  const CustomizationColor({
    required this.color,
    required this.derivations,
    required this.displayName,
    required this.description,
  });

  Color? get second => derivations['second'];
  Color? get third => derivations['third'];
  Color? get card => derivations['card'];
  Color? get popup => derivations['popup'];
  Color? get dark => derivations['dark'];
  Color? get light => derivations['light'];

  factory CustomizationColor.fromJson(Map<String, dynamic> json) {
    return CustomizationColor(
      color: parseColorValue(json['color']),
      derivations: _parseDerivations(json['derivations']),
      displayName: (json['display_name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }

  /// Parses a `ColorValue` wire object (`{oklch, hsl, rgb, hex}`)
  /// into a Flutter [Color] by reading its `rgb` block. Returns
  /// `null` on any malformed input. Exposed so the root parser can
  /// reuse it for the flat `palette` block (whose entries are bare
  /// `ColorValue`s, not full `ColorOutput`s).
  static Color? parseColorValue(Object? raw) {
    if (raw is! Map) return null;
    final rgb = raw['rgb'];
    if (rgb is! Map) return null;
    final r = (rgb['r'] as num?)?.toInt();
    final g = (rgb['g'] as num?)?.toInt();
    final b = (rgb['b'] as num?)?.toInt();
    final alpha = (rgb['alpha'] as num?)?.toDouble() ?? 1.0;
    if (r == null || g == null || b == null) return null;
    return Color.fromARGB(
      (alpha * 255).round().clamp(0, 255),
      r.clamp(0, 255),
      g.clamp(0, 255),
      b.clamp(0, 255),
    );
  }

  static Map<String, Color> _parseDerivations(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, Color>{};
    raw.forEach((key, value) {
      if (key is! String) return;
      final color = parseColorValue(value);
      if (color != null) result[key] = color;
    });
    return result;
  }

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'description': description,
  };

  @override
  List<Object?> get props => [color, derivations, displayName, description];
}
