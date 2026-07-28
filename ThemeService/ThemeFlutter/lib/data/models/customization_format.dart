import 'package:equatable/equatable.dart';

/// One resolved layout/motion format on the wire.
///
/// Unlike a colour or a copy string, a format carries the generator's
/// own justification for the arrangement it chose. That [reason] is the
/// only place a human reviewing a generated redesign can read *why* a
/// screen was rearranged, so the engine keeps it rather than flattening
/// the entry to its value.
class ThemeFormatValue extends Equatable {
  const ThemeFormatValue({required this.value, this.reason = ''});

  /// The enum value name, e.g. `compactRail`. The engine does not know
  /// the app's format vocabulary and deliberately does not validate it:
  /// the app parses this against its own enum and falls back to its
  /// shipped arrangement when the name is unknown, so a vocabulary the
  /// service is ahead of can never break a screen.
  final String value;

  /// The generator's rationale for this arrangement. Empty when the
  /// wire omits it.
  final String reason;

  factory ThemeFormatValue.fromJson(Map<String, dynamic> json) {
    final value = json['value'];
    if (value is! String || value.isEmpty) {
      throw const FormatException('format slot has no value');
    }
    final reason = json['reason'];
    return ThemeFormatValue(
      value: value,
      reason: reason is String ? reason : '',
    );
  }

  Map<String, dynamic> toJson() => {'value': value, 'reason': reason};

  @override
  List<Object?> get props => [value, reason];
}
