/// Hardcoded summary numbers shown in the Dashboard total-members
/// donut card. Field names match the future API shape so the swap to a
/// real repository is mechanical.
class MemberStatsSummary {
  final int total;
  final int active;
  final int inactive;

  const MemberStatsSummary({
    required this.total,
    required this.active,
    required this.inactive,
  });
}

const MemberStatsSummary kMockMemberStats = MemberStatsSummary(
  total: 154,
  active: 123,
  inactive: 31,
);
