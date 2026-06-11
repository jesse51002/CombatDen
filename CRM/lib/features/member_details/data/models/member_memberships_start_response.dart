import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';

part 'member_memberships_start_response.g.dart';

/// Response after a start: the per-membership breakdown.
///
/// Mirrors the backend `MemberMembershipsStartResponse`.
/// A 201 with this body is NOT success/fail — each item in
/// [results] carries its own created/failed status.
/// [chargeCount] = (1 if any one-time membership) + (1 if
/// any recurring); [multipleCharges] flags the mixed case so
/// the UI can say two separate charges occurred.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberMembershipsStartResponse extends Equatable {
  @JsonKey(defaultValue: [])
  final List<MemberMembershipsStartResultItem> results;
  final int chargeCount;
  final bool multipleCharges;

  const MemberMembershipsStartResponse({
    this.results = const [],
    required this.chargeCount,
    required this.multipleCharges,
  });

  factory MemberMembershipsStartResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberMembershipsStartResponseFromJson(json);

  List<MemberMembershipsStartResultItem> get failed =>
      results.where((r) => r.isFailed).toList();

  bool get hasFailures => failed.isNotEmpty;

  @override
  List<Object?> get props => [
        results,
        chargeCount,
        multipleCharges,
      ];
}
