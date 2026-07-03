/// Display-only mirror of the backend render (WaiversSignatures._render):
/// replaces {{key}} when [values] has a non-empty value for key; any other
/// token is left literally. The backend render of the stored rendered_body
/// stays authoritative.
library;

final RegExp _placeholder = RegExp(r'\{\{(\w+)\}\}');

// A token as a markdown serializer may have stored it: braces/underscores
// optionally backslash-escaped (`\{\{member\_name\}\}`). Displays identically
// after markdown parsing, so it must render the same as the clean form.
final RegExp _escapedPlaceholder =
    RegExp(r'\\?\{\\?\{((?:\w|\\_)+)\\?\}\\?\}');

/// Substitute `{{key}}` tokens in [body] with the matching entry from
/// [values]. A token is only replaced when [values] holds a **non-empty**
/// value for its key; a missing key or an empty value leaves the token
/// literal. Tolerates markdown-escaped tokens (canonicalized first) so
/// bodies saved before the editor unescaped on save still render.
String renderWaiverPlaceholders(String body, Map<String, String> values) {
  final canonical = body.replaceAllMapped(
    _escapedPlaceholder,
    (m) => '{{${m.group(1)!.replaceAll(r'\_', '_')}}}',
  );
  return canonical.replaceAllMapped(_placeholder, (match) {
    final key = match.group(1)!;
    final value = values[key];
    if (value == null || value.isEmpty) return match.group(0)!;
    return value;
  });
}

/// Today's date in UTC as `YYYY-MM-DD`, matching the backend's `date`
/// placeholder fill (`datetime.now(UTC).date().isoformat()`), so the preview
/// shows the same date the backend will stamp.
String waiverSignDateUtc() {
  final now = DateTime.now().toUtc();
  final year = now.year.toString().padLeft(4, '0');
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
