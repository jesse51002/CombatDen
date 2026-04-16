import 'package:intl/intl.dart';

/// Formats a money amount stored as minor currency units
/// (e.g. cents for USD) into a human-readable display
/// string such as `$50` or `-$12.34`.
///
/// **Storage contract:** every money value in the app is
/// stored as a signed integer in the smallest unit of the
/// currency. Conversion to a display string only happens
/// at the render layer, via this helper.
///
/// - [minorUnits] is signed: negative values render with a
///   leading minus sign (e.g. refunds).
/// - [currency] is the ISO 4217 code coming from the
///   backend. Defaults to `usd`.
/// - [decimalDigits] controls the fractional digits; set to
///   `2` if you want cents visible, `0` (default) for a
///   whole-dollar look.
String formatMinorUnits(
  int minorUnits, {
  String currency = 'usd',
  int decimalDigits = 2,
}) {
  final symbol = _symbolFor(currency);
  final formatter = NumberFormat.currency(
    locale: 'en_US',
    symbol: symbol,
    decimalDigits: decimalDigits,
  );
  return formatter.format(minorUnits / 100);
}

String _symbolFor(String currency) {
  switch (currency.toLowerCase()) {
    case 'usd':
      return '\$';
    case 'eur':
      return '€';
    case 'gbp':
      return '£';
    default:
      return '${currency.toUpperCase()} ';
  }
}
