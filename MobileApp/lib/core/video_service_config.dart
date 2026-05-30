/// VideoService deployment config, shared by the gym detail (classes +
/// rewards) and the video feed. Both fetch this single-tenant build's content
/// from the VideoService by **gym id** (`GET /gyms/{gymId}` for the whole
/// detail, read into memory once; `GET /gyms/{gymId}/videos` for the paginated
/// feed). The gym id is the user-selected gym (`SelectedGym`); the theme it
/// carries is branding-only.
///
/// Base URL defaults to localhost (use `adb reverse tcp:8002 tcp:8002` so a
/// device reaches the host over USB), overridable at launch with
/// `--dart-define=VIDEO_BASE_URL=http://<host-LAN-IP>:8002`.
const String kVideoBaseUrl = String.fromEnvironment(
  'VIDEO_BASE_URL',
  defaultValue: 'http://localhost:8002',
);
