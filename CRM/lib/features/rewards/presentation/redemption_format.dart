/// The one relative "requested at" formatter for redemption surfaces —
/// `Today, 3:05 PM` for a same-day instant, `Jun 12, 3:05 PM` otherwise.
/// Shared by the queue card and the approve/reject dialog so the two can
/// never drift.
String formatRedemptionDate(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final isToday = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final hour = local.hour > 12
      ? local.hour - 12
      : (local.hour == 0 ? 12 : local.hour);
  final amPm = local.hour >= 12 ? 'PM' : 'AM';
  final min = local.minute.toString().padLeft(2, '0');
  if (isToday) return 'Today, $hour:$min $amPm';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, $hour:$min $amPm';
}
