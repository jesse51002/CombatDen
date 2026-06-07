import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'membership_member_info.g.dart';

/// Per-member slice of a grouped [MembershipInfo] — the
/// `member_memberships` row's item id for that person,
/// plus any scheduled end or cancellation date.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembershipMemberInfo extends Equatable {
  /// ID of the underlying `member_memberships` row — the
  /// handle used by per-membership mutations (cancel,
  /// update price, mark-paid-cash, discount add/remove).
  final String itemId;

  /// Natural end date of the membership (e.g. the final
  /// day of a one-time pass). Null for recurring plans
  /// that have no scheduled end.
  final DateTime? endDate;

  /// Effective cancellation date — access ends after this
  /// day. Set once staff cancel the membership; null while
  /// the membership is still active.
  final DateTime? cancelDate;

  /// True when the member is still billed at a price that
  /// no longer matches the current plan cost — i.e. the
  /// plan price changed but this member was not migrated
  /// to the new price.
  @JsonKey(defaultValue: false)
  final bool onOutdatedPrice;

  /// This member's own pinned price (minor units) — what
  /// they are actually billed before discounts. Lets the
  /// card render the cost atomically for one member.
  @JsonKey(defaultValue: 0)
  final int baseCost;

  /// This member's own after-discount total (minor units).
  @JsonKey(defaultValue: 0)
  final int totalPrice;

  const MembershipMemberInfo({
    required this.itemId,
    this.endDate,
    this.cancelDate,
    this.onOutdatedPrice = false,
    this.baseCost = 0,
    this.totalPrice = 0,
  });

  factory MembershipMemberInfo.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembershipMemberInfoFromJson(json);

  /// The soonest upcoming exit date for this member — the
  /// earlier of [cancelDate] and [endDate] — along with
  /// which kind it is. Returns null when neither is set.
  MembershipExitDate? get exitDate {
    final c = cancelDate;
    final e = endDate;
    if (c == null && e == null) return null;
    if (c == null) {
      return MembershipExitDate(
        date: e!,
        kind: MembershipExitKind.ending,
      );
    }
    if (e == null) {
      return MembershipExitDate(
        date: c,
        kind: MembershipExitKind.cancelling,
      );
    }
    return c.isBefore(e)
        ? MembershipExitDate(
            date: c,
            kind: MembershipExitKind.cancelling,
          )
        : MembershipExitDate(
            date: e,
            kind: MembershipExitKind.ending,
          );
  }

  @override
  List<Object?> get props => [
        itemId,
        endDate,
        cancelDate,
        onOutdatedPrice,
        baseCost,
        totalPrice,
      ];
}

enum MembershipExitKind { cancelling, ending }

class MembershipExitDate extends Equatable {
  final DateTime date;
  final MembershipExitKind kind;

  const MembershipExitDate({
    required this.date,
    required this.kind,
  });

  @override
  List<Object?> get props => [date, kind];
}
