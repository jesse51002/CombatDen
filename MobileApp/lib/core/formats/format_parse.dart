/// Shared resilient parser for every layout and motion format enum.
///
/// Format values arrive as plain strings from the customization wire, so
/// parsing must never throw and must never leave a screen without a
/// layout. Every enum in this folder therefore falls back to the value
/// that ships today rather than to an `unknown` variant: an unknown
/// layout still has to render something, and the shipped arrangement is
/// the only safe choice.
///
/// Matching is case-insensitive and trims surrounding whitespace so a
/// hand-edited `app.yaml` ("  AgendaList ") resolves the same as the
/// generated one.
T parseFormat<T extends Enum>(
  List<T> values,
  String? wire,
  T fallback,
) {
  if (wire == null) return fallback;
  final needle = wire.trim().toLowerCase();
  if (needle.isEmpty) return fallback;
  return values.firstWhere(
    (value) => value.name.toLowerCase() == needle,
    orElse: () => fallback,
  );
}
