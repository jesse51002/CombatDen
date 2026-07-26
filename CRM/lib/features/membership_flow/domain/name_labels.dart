/// How BOTH membership-purchase surfaces read a list of people out loud.
///
/// It sits beside `plan_labels.dart` for the same reason that one does: a
/// sentence naming two children on one charge must read identically at the
/// desk and on the member's screen, and the mechanism keeping that true is the
/// import graph rather than a comment.
library;

/// "Ella and Theo" — a natural list of first names, so a money line reads like
/// a sentence a parent would say rather than a comma-separated dump.
String flowNameList(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
}
