import 'package:equatable/equatable.dart';

/// A loaded lottie override for one slot. Mirrors the API's `LottieWire`:
/// where to fetch the preset `.json` ([url]) plus the recolour /reveal
/// metadata the app applies at render time.
///
/// [regionRoles] maps a Lottie layer name to a palette ROLE key (never a
/// resolved colour) — the app resolves the key against its own live
/// palette so a palette shift re-tints the animation for free. [reveals]
/// and [insertionPoint] are set only for reveal-type slots (both `null`
/// for the standalone slots this app uses today). Parsing is resilient:
/// an absent/malformed field degrades to `{}` / `null`, never throwing.
class LottieOverride extends Equatable {
  const LottieOverride({
    required this.url,
    required this.regionRoles,
    this.reveals,
    this.insertionPoint,
  });

  /// Slot URL of the preset `.json` (still relative on the wire; the
  /// resolver absolutises it). Empty means "no usable override".
  final String url;

  /// Layer name -> palette role key (e.g. `core_fill` -> `primary`).
  final Map<String, String> regionRoles;

  /// Reveal slots only: the image slot id this animation reveals.
  final String? reveals;

  /// Reveal slots only: where the revealed image composites.
  final LottieInsertionPoint? insertionPoint;

  factory LottieOverride.fromJson(Map<String, dynamic> json) {
    return LottieOverride(
      url: (json['url'] as String?) ?? '',
      regionRoles: _parseRegionRoles(json['region_roles']),
      reveals: json['reveals'] as String?,
      insertionPoint: LottieInsertionPoint.tryFromJson(
        json['insertion_point'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'region_roles': Map<String, String>.from(regionRoles),
    if (reveals != null) 'reveals': reveals,
    if (insertionPoint != null) 'insertion_point': insertionPoint!.toJson(),
  };

  static Map<String, String> _parseRegionRoles(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value is String && value.isNotEmpty) {
        result[key] = value;
      }
    });
    return result;
  }

  @override
  List<Object?> get props => [url, regionRoles, reveals, insertionPoint];
}

/// Where a reveal preset composites the revealed image, normalised to the
/// animation's composition box (top-left origin, 0..1). Standalone slots
/// never carry one.
class LottieInsertionPoint extends Equatable {
  const LottieInsertionPoint({
    required this.frame,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int frame;
  final double x;
  final double y;
  final double width;
  final double height;

  /// Returns `null` for an absent or non-map value, so a malformed point
  /// never fails the whole payload.
  static LottieInsertionPoint? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final frame = raw['frame'];
    final x = raw['x'];
    final y = raw['y'];
    final width = raw['width'];
    final height = raw['height'];
    if (frame is! num || x is! num || y is! num || width is! num ||
        height is! num) {
      return null;
    }
    return LottieInsertionPoint(
      frame: frame.toInt(),
      x: x.toDouble(),
      y: y.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'frame': frame,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  @override
  List<Object?> get props => [frame, x, y, width, height];
}
