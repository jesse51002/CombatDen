import 'dart:developer';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// The platform's native maps URI for a free-text [address].
///
/// Android hands the query to whatever handles the `geo:` scheme (Google Maps,
/// Waze, …); iOS opens Apple Maps. The address is user-entered free text, so it
/// is percent-encoded verbatim and never parsed.
Uri mapsUriFor(String address) {
  final q = Uri.encodeComponent(address.trim());
  if (Platform.isAndroid) return Uri.parse('geo:0,0?q=$q');
  return Uri.parse('https://maps.apple.com/?q=$q');
}

/// Open [address] in the phone's native map app. Returns false when no handler
/// took the intent (or launching threw) so the caller can surface a message.
Future<bool> launchMapsFor(String address) async {
  try {
    return await launchUrl(
      mapsUriFor(address),
      mode: LaunchMode.externalApplication,
    );
  } catch (e, st) {
    log('launchMapsFor failed', error: e, stackTrace: st);
    return false;
  }
}
