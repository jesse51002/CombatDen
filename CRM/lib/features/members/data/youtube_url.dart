/// YouTube-URL parsing shared by the videos tab.
///
/// Mirrors the backend's `VideosService._extract_youtube_id` so the CRM's
/// client-side "is this a valid YouTube link?" check matches exactly what the
/// `POST /api/v1/gyms/{id}/videos` endpoint will accept. Used both to validate
/// the "Add custom video" input and to recover a video's id from its canonical
/// watch URL (for the remove call).
library;

final RegExp _youtubeIdRe = RegExp(r'^[A-Za-z0-9_-]{11}$');
const Set<String> _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'youtu.be',
};
// Path-style links carry the id as the segment after one of these prefixes
// (`/embed/<id>`, `/shorts/<id>`, `/v/<id>`, `/live/<id>`).
const Set<String> _youtubePathPrefixes = {'embed', 'shorts', 'v', 'live'};

/// The 11-char YouTube video id in [url], or null when [url] isn't a
/// recognisable YouTube link. Handles `watch?v=`, `youtu.be/<id>`,
/// `/embed/<id>`, `/shorts/<id>`, `/v/<id>`, `/live/<id>`, and a bare id.
String? extractYoutubeId(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;
  // A bare id pasted on its own.
  if (_youtubeIdRe.hasMatch(raw)) return raw;

  final uri = Uri.tryParse(raw.contains('//') ? raw : 'https://$raw');
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (!_youtubeHosts.contains(host)) return null;

  String? candidate;
  if (host == 'youtu.be') {
    candidate = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (uri.path == '/watch') {
    candidate = uri.queryParameters['v'];
  } else {
    final segments = uri.pathSegments;
    candidate =
        (segments.length >= 2 && _youtubePathPrefixes.contains(segments.first))
        ? segments[1]
        : null;
  }
  if (candidate == null || !_youtubeIdRe.hasMatch(candidate)) return null;
  return candidate;
}
