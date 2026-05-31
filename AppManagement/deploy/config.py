import json
from pathlib import Path

DOMAIN = "app.combatden.net"
BUCKET = "combatden-app"
REGION = "us-east-1"
PROJECT_TAG = "combatden-app"

DEPLOY_DIR = Path(__file__).resolve().parent
# The built Flutter web bundle (deploy/ lives under AppManagement/).
# Produced by: flutter build web --release --base-href=/ \
#   --dart-define=CUST_BASE_URL=https://theme.combatden.net \
#   --dart-define=VIDEO_BASE_URL=https://video.combatden.net
SITE_DIR = DEPLOY_DIR.parent / "build" / "web"
STATE_FILE = DEPLOY_DIR / ".deploy-state.json"

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".mjs": "application/javascript; charset=utf-8",
    ".json": "application/json",
    ".wasm": "application/wasm",  # canvaskit — must be served as wasm
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".ico": "image/x-icon",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
    ".txt": "text/plain; charset=utf-8",
    ".map": "application/json",
    ".bin": "application/octet-stream",
}


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    return json.loads(STATE_FILE.read_text())


def save_state(**kwargs) -> dict:
    state = load_state()
    state.update(kwargs)
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True))
    return state


def content_type_for(path: Path) -> str:
    return CONTENT_TYPES.get(path.suffix.lower(), "application/octet-stream")
