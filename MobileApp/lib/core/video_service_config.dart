/// VideoService deployment config, shared by the video feed and class-card
/// features. Both fetch the active theme's content from the VideoService by
/// **design id** (`GET /themes/{designId}/...`, single-tenant) — the
/// theme→gym→feed mapping lives server-side, so the app no longer carries any
/// theme→feed table.
///
/// Base URL defaults to localhost (use `adb reverse tcp:8002 tcp:8002` so a
/// device reaches the host over USB), overridable at launch with
/// `--dart-define=VIDEO_BASE_URL=http://<host-LAN-IP>:8002`.
const String kVideoBaseUrl = String.fromEnvironment(
  'VIDEO_BASE_URL',
  defaultValue: 'http://localhost:8002',
);
