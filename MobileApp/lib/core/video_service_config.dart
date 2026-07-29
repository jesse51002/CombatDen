/// NOTE: the standalone VideoService HTTP API on :8002 no longer exists;
/// it was merged into the FastApiBackend (pivot 2026-06-24). This content
/// is served publicly at /api/v1/presets/templates.
/// VideoService deployment config, shared by the gym detail (classes +
/// rewards) and the video feed. Both fetch this single-tenant build's content
/// from the VideoService by **gym id** (`GET /gyms/{gymId}` for the whole
/// detail, read into memory once; `GET /gyms/{gymId}/videos` for the paginated
/// feed). The gym id is the user-selected gym (`SelectedGym`); the theme it
/// carries is branding-only.
///
/// Base URL defaults to localhost (use `adb reverse tcp:8000 tcp:8000` so a
/// device reaches the host over USB), overridable at launch with
/// `--dart-define=VIDEO_BASE_URL=http://<host-LAN-IP>:8000/api/v1`.
const String kVideoBaseUrl = String.fromEnvironment(
  'VIDEO_BASE_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);
