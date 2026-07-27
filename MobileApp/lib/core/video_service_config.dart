/// Base URL for the gym CONTENT read API — the gym browser, the gym
/// detail (classes + rewards) and the video feed.
///
/// This content is served by the **FastApiBackend** under
/// `/api/v1/presets/templates…`. The standalone VideoService that used
/// to serve it on port 8002 no longer has an HTTP API at all: it was
/// merged into the backend (see
/// `docs/Business/pivots/2026-06-24-22-videoservice-api-merged-into-backend.md`)
/// and only its batch worker remains. Pointing at 8002 fails with a
/// connection error, which surfaces as "Could not load gyms".
///
/// The endpoints, all public (no auth):
///   GET /presets/templates                      the gym browser
///   GET /presets/templates/{id}                 classes + rewards
///   GET /presets/templates/{id}/videos/preview  the home feed
///   GET /presets/templates/{id}/videos          one genre
///
/// Defaults to localhost (use `adb reverse tcp:8000 tcp:8000` so a
/// device reaches the host over USB), overridable at launch with
/// `--dart-define=VIDEO_BASE_URL=http://<host-LAN-IP>:8000/api/v1`.
/// The define keeps its old name so existing launch configs and scripts
/// keep working.
const String kVideoBaseUrl = String.fromEnvironment(
  'VIDEO_BASE_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);
