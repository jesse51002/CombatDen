import 'package:equatable/equatable.dart';

/// A loaded lottie override for one slot. Mirrors the API's `LottieWire`:
/// where to fetch the baked `.json` ([url]) plus the playback metadata the
/// app renders with.
///
/// The colour is baked into the served file by the pipeline, so there is no
/// recolour map — the app plays the animation as-is at [speed]. [reveals],
/// [insertionPoint] and [holdSeconds] are set only for reveal-type slots
/// (all `null` for the standalone slots this app uses today). Parsing is
/// resilient: an absent/malformed field degrades to a sensible default,
/// never throwing.
class LottieOverride extends Equatable {
  const LottieOverride({
    required this.url,
    this.speed = 1.0,
    this.reveals,
    this.insertionPoint,
    this.holdSeconds,
  });

  /// Slot URL of the baked `.json` (still relative on the wire; the
  /// resolver absolutises it). Empty means "no usable override".
  final String url;

  /// Playback multiplier applied to the animation duration (2.0 => plays in
  /// half the time). Defaults to 1.0.
  final double speed;

  /// Reveal slots only: the image slot id this animation reveals.
  final String? reveals;

  /// Reveal slots only: where the revealed image composites.
  final LottieInsertionPoint? insertionPoint;

  /// Reveal slots only: how long (seconds) the revealed image holds before
  /// it and the animation end (the animation is cut short if still playing).
  final double? holdSeconds;

  factory LottieOverride.fromJson(Map<String, dynamic> json) {
    final speed = json['speed'];
    final hold = json['hold_seconds'];
    return LottieOverride(
      url: (json['url'] as String?) ?? '',
      speed: speed is num && speed > 0 ? speed.toDouble() : 1.0,
      reveals: json['reveals'] as String?,
      insertionPoint: LottieInsertionPoint.tryFromJson(
        json['insertion_point'],
      ),
      holdSeconds: hold is num && hold > 0 ? hold.toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'speed': speed,
    if (reveals != null) 'reveals': reveals,
    if (insertionPoint != null) 'insertion_point': insertionPoint!.toJson(),
    if (holdSeconds != null) 'hold_seconds': holdSeconds,
  };

  @override
  List<Object?> get props => [
    url,
    speed,
    reveals,
    insertionPoint,
    holdSeconds,
  ];
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
