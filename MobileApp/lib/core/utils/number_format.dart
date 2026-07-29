/// Formats an integer count with thousand-separator commas — the app-wide
/// display convention for points balances and other large counts
/// (e.g. `1250` -> `1,250`, `980` -> `980`). Negative values keep their sign.
String formatCount(int n) {
  if (n > -1000 && n < 1000) return '$n';
  final negative = n < 0;
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}
