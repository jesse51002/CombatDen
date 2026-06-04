import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

part 'member_row.g.dart';

/// Base class for all member list row types.
///
/// Each view returns a different row shape from the API.
/// The [fromJson] factory dispatches to the correct
/// subtype based on [view].
sealed class MemberRow extends Equatable {
  final String memberId;
  final String name;
  final String? avatarUrl;

  const MemberRow({
    required this.memberId,
    required this.name,
    this.avatarUrl,
  });

  /// Dispatches JSON to the correct row subtype based
  /// on [view].
  static MemberRow fromJson(
    Map<String, dynamic> json,
    MembersListView view,
  ) {
    return switch (view) {
      MembersListView.all =>
        AllViewRow.fromJson(json),
      MembersListView.trial =>
        TrialViewRow.fromJson(json),
      MembersListView.frozen =>
        FrozenViewRow.fromJson(json),
      MembersListView.overdue =>
        OverdueViewRow.fromJson(json),
    };
  }
}

/// Row for the All view.
///
/// Includes contact, membership badge, and last class.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class AllViewRow extends MemberRow {
  final String? email;
  @JsonKey(
    fromJson: MembershipStatus.fromJson,
  )
  final MembershipStatus membershipStatus;
  final String membershipText;
  final int? daysSinceLastClass;

  const AllViewRow({
    required super.memberId,
    required super.name,
    super.avatarUrl,
    this.email,
    required this.membershipStatus,
    required this.membershipText,
    this.daysSinceLastClass,
  });

  factory AllViewRow.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$AllViewRowFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        name,
        avatarUrl,
        email,
        membershipStatus,
        membershipText,
        daysSinceLastClass,
      ];
}

/// Row for the Trial view.
///
/// Includes trial period dates and days remaining.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class TrialViewRow extends MemberRow {
  final int daysRemaining;
  final String startDate;
  final String endDate;

  const TrialViewRow({
    required super.memberId,
    required super.name,
    super.avatarUrl,
    required this.daysRemaining,
    required this.startDate,
    required this.endDate,
  });

  factory TrialViewRow.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$TrialViewRowFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        name,
        avatarUrl,
        daysRemaining,
        startDate,
        endDate,
      ];
}

/// Row for the Frozen view.
///
/// Includes freeze period and membership price.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class FrozenViewRow extends MemberRow {
  final String freezeStart;
  final int daysUntilUnfrozen;
  final String freezeEnd;
  final String price;

  const FrozenViewRow({
    required super.memberId,
    required super.name,
    super.avatarUrl,
    required this.freezeStart,
    required this.daysUntilUnfrozen,
    required this.freezeEnd,
    required this.price,
  });

  factory FrozenViewRow.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$FrozenViewRowFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        name,
        avatarUrl,
        freezeStart,
        daysUntilUnfrozen,
        freezeEnd,
        price,
      ];
}

/// Row for the Overdue view.
///
/// Shows members with overdue payments.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class OverdueViewRow extends MemberRow {
  final String? email;
  final String? phone;
  final String membershipText;
  final int daysLate;

  const OverdueViewRow({
    required super.memberId,
    required super.name,
    super.avatarUrl,
    this.email,
    this.phone,
    required this.membershipText,
    required this.daysLate,
  });

  factory OverdueViewRow.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$OverdueViewRowFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        name,
        avatarUrl,
        email,
        phone,
        membershipText,
        daysLate,
      ];
}
