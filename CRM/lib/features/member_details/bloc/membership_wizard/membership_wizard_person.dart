import 'package:equatable/equatable.dart';

/// One row of the staff flow's roster — a person this run may charge for.
///
/// The payer sits in the same list as everybody else and carries [isPayer]
/// rather than living in a field of their own, because the `who` step is ONE
/// roster: the payer pill and the "getting a membership" check are two
/// controls on the same row. A payer who buys nothing themselves is an
/// ordinary row with [training] false — `payer_member_id` is identity-only
/// server-side, so paying for somebody else's membership without holding one
/// is a normal sale, not an edge case.
class MembershipWizardPerson extends Equatable {
  final String memberId;
  final String name;
  final String? email;
  final String? photoUrl;

  /// Whose card (or cash) settles this run. Exactly one row carries it.
  final bool isPayer;

  /// Whether this person is getting a membership — whether they are in the
  /// CART at all, and therefore whether the plans step is walked for them.
  final bool training;

  const MembershipWizardPerson({
    required this.memberId,
    required this.name,
    this.email,
    this.photoUrl,
    this.isPayer = false,
    this.training = false,
  });

  /// The first word of [name], for a sentence that addresses them. Empty when
  /// there is nothing to take.
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final space = trimmed.indexOf(' ');
    return space < 0 ? trimmed : trimmed.substring(0, space);
  }

  MembershipWizardPerson copyWith({
    bool? isPayer,
    bool? training,
  }) =>
      MembershipWizardPerson(
        memberId: memberId,
        name: name,
        email: email,
        photoUrl: photoUrl,
        isPayer: isPayer ?? this.isPayer,
        training: training ?? this.training,
      );

  @override
  List<Object?> get props => [
        memberId,
        name,
        email,
        photoUrl,
        isPayer,
        training,
      ];
}
