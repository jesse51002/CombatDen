// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_memberships_start_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberMembershipsStartPreview _$MemberMembershipsStartPreviewFromJson(
  Map<String, dynamic> json,
) => MemberMembershipsStartPreview(
  oneTime: json['one_time'] == null
      ? null
      : PreviewInvoice.fromJson(json['one_time'] as Map<String, dynamic>),
  dueNow: json['due_now'] == null
      ? null
      : PreviewInvoice.fromJson(json['due_now'] as Map<String, dynamic>),
  recurring: json['recurring'] == null
      ? null
      : PreviewInvoice.fromJson(json['recurring'] as Map<String, dynamic>),
);
