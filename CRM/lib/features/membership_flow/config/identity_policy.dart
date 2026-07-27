import 'package:equatable/equatable.dart';

/// How much of a person's ADDRESS a surface may print beside their name.
///
/// The two surfaces read the same roster in different rooms. A lobby iPad has
/// a queue reading over the member's shoulder and lists people adopted from
/// the gym's own records — addresses nobody standing there typed — so it says
/// enough to RECOGNISE and never enough to copy. A staff desk is the gym's own
/// screen looking at the gym's own records, and staff correcting a typo need
/// the whole address.
///
/// A policy object rather than a `maskEmails: true` flag for the same reason
/// the discounts capability is one: a boolean is one wrong default away from
/// printing a stranger's address on a shared screen, whereas a surface that
/// wants the masked reading has to say so by NAME.
class IdentityPolicy extends Equatable {
  /// Whether an address is reduced to its recognisable shape before printing.
  final bool masks;

  /// The member-facing reading — the lobby iPad's.
  const IdentityPolicy.masked() : masks = true;

  /// The staff reading — the desk's own records, in full.
  const IdentityPolicy.full() : masks = false;

  /// The one quiet line under a person's name, or null when there is nothing
  /// to print (which drops the line rather than leaving a blank one).
  ///
  /// The masked form keeps the first character and the whole domain —
  /// `e•••••@bell.family` — because that is exactly what a parent needs to
  /// recognise their own child's address and not enough for the person behind
  /// them to write down. An address with no local part to mask (no `@`, or an
  /// `@` in first position) is passed through untouched: there is nothing to
  /// hide, and inventing a mask around it would only make it unrecognisable.
  String? identityLine(String? email) {
    final trimmed = email?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!masks) return trimmed;
    final at = trimmed.indexOf('@');
    if (at < 1) return trimmed;
    return '${trimmed[0]}•••••${trimmed.substring(at)}';
  }

  @override
  List<Object?> get props => [masks];
}
