import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';

part 'member_memberships_start_preview.g.dart';

/// The start preview's three-way invoice split.
///
/// Mirrors the backend
/// `MemberMembershipsStartPreviewResponse`:
/// [oneTime] — the consolidated one-time invoice (all
/// one-time / trial memberships, one charge; trials appear
/// as $0 lines). [dueNow] — the recurring proration invoice
/// charged immediately (`proration_behavior=prorate_to_anchor`).
/// [recurring] — the steady-state invoice each cycle going forward.
/// Each is null when the request has no memberships in that
/// group.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberMembershipsStartPreview extends Equatable {
  final PreviewInvoice? oneTime;
  final PreviewInvoice? dueNow;
  final PreviewInvoice? recurring;

  const MemberMembershipsStartPreview({
    this.oneTime,
    this.dueNow,
    this.recurring,
  });

  factory MemberMembershipsStartPreview.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberMembershipsStartPreviewFromJson(json);

  bool get isEmpty =>
      oneTime == null && dueNow == null && recurring == null;

  @override
  List<Object?> get props => [oneTime, dueNow, recurring];
}
