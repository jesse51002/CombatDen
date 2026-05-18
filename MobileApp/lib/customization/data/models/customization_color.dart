import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// One resolved brand colour. App-agnostic leaf type.
///
/// The service emits colours in **OKLCH** (CSS form, e.g.
/// `oklch(70.523% 0.1936 41.09)`). [oklch] keeps that raw string
/// for a loss-free `toJson`; [color] is the parsed sRGB value, or
/// `null` when the string is missing/unparseable — callers then
/// fall back to their bundled default.
class CustomizationColor extends Equatable {
  /// Raw `oklch(L C H[ / A])` string from the service.
  final String? oklch;

  /// Parsed sRGB colour, or `null` if [oklch] could not be parsed.
  final Color? color;

  /// Human label, e.g. "Cage Orange".
  final String displayName;

  /// Purpose/usage prose for the colour.
  final String description;

  const CustomizationColor({
    required this.oklch,
    required this.color,
    required this.displayName,
    required this.description,
  });

  factory CustomizationColor.fromJson(Map<String, dynamic> json) {
    final oklch = json['oklch'] as String?;
    return CustomizationColor(
      oklch: oklch,
      color: _parseOklch(oklch),
      displayName: (json['display_name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'oklch': oklch,
    'display_name': displayName,
    'description': description,
  };

  /// Tolerant `oklch(L C H[ / A])` → sRGB parser. Accepts L as a
  /// percentage or 0–1 number, C as a number or percentage
  /// (100% = 0.4), H in deg/rad/grad/turn, optional alpha.
  /// Returns `null` on any malformed value so the call site can
  /// fall back. Conversion: OKLCH → OKLab → linear sRGB → gamma.
  static Color? _parseOklch(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (!s.startsWith('oklch(') || !s.endsWith(')')) return null;
    var inner = s.substring(6, s.length - 1).trim();

    double alpha = 1;
    final slash = inner.indexOf('/');
    if (slash != -1) {
      final a = _num(inner.substring(slash + 1).trim(), scale: 1);
      if (a == null) return null;
      alpha = a.clamp(0.0, 1.0);
      inner = inner.substring(0, slash).trim();
    }

    final parts = inner
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length != 3) return null;

    final l = _num(parts[0], scale: 1); // % → 0–1, else 0–1
    final c = _num(parts[1], scale: 0.4); // % → ×0.4, else as-is
    final h = _hueDegrees(parts[2]);
    if (l == null || c == null || h == null) return null;

    final lc = l.clamp(0.0, 1.0);
    final cc = c < 0 ? 0.0 : c;
    final hr = h * math.pi / 180.0;
    final a = cc * math.cos(hr);
    final b = cc * math.sin(hr);

    // OKLab → linear sRGB (Björn Ottosson).
    final l_ = lc + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = lc - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = lc - 0.0894841775 * a - 1.2914855480 * b;
    final lCube = l_ * l_ * l_;
    final mCube = m_ * m_ * m_;
    final sCube = s_ * s_ * s_;

    final rLin =
        4.0767416621 * lCube - 3.3077115913 * mCube + 0.2309699292 * sCube;
    final gLin =
        -1.2684380046 * lCube + 2.6097574011 * mCube - 0.3413193965 * sCube;
    final bLin =
        -0.0041960863 * lCube - 0.7034186147 * mCube + 1.7076147010 * sCube;

    return Color.fromARGB(
      (alpha * 255).round().clamp(0, 255),
      _channel(rLin),
      _channel(gLin),
      _channel(bLin),
    );
  }

  /// Linear-sRGB (gamut-clamped) → gamma-encoded 0–255.
  static int _channel(double linear) {
    final x = linear.clamp(0.0, 1.0);
    final encoded = x <= 0.0031308
        ? 12.92 * x
        : 1.055 * math.pow(x, 1 / 2.4) - 0.055;
    return (encoded * 255).round().clamp(0, 255);
  }

  /// Parses `none`, a plain number, or a percentage. A percentage
  /// is divided by 100 then multiplied by [scale]; a plain number
  /// is returned as-is. `null` on garbage.
  static double? _num(String t, {required double scale}) {
    if (t == 'none') return 0;
    if (t.endsWith('%')) {
      final v = double.tryParse(t.substring(0, t.length - 1));
      return v == null ? null : v / 100.0 * scale;
    }
    return double.tryParse(t);
  }

  /// Hue token → degrees. Supports deg (default), rad, grad,
  /// turn, and `none`.
  static double? _hueDegrees(String t) {
    if (t == 'none') return 0;
    for (final u in const ['grad', 'deg', 'rad', 'turn']) {
      if (t.endsWith(u)) {
        final v = double.tryParse(t.substring(0, t.length - u.length));
        if (v == null) return null;
        switch (u) {
          case 'rad':
            return v * 180.0 / math.pi;
          case 'grad':
            return v * 0.9;
          case 'turn':
            return v * 360.0;
          default:
            return v;
        }
      }
    }
    return double.tryParse(t);
  }

  @override
  List<Object?> get props => [oklch, color, displayName, description];
}
