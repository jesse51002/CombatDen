"""Config + state for provisioning the ThemeService asset CDN.

A private S3 bucket (`combatden-assets`) fronted by CloudFront at
`cdn.combatden.net` (OAC). Mirrors `../../AppManagement/deploy/` but for an asset
CDN: no SPA error-rewrite, and a custom cache policy that keys on the `?v=`
query string (so the API's content-fingerprint busts the cache). Asset *upload*
is the main package's `make sync-assets`; this dir only provisions the infra.
"""

import json
from pathlib import Path

DOMAIN = "cdn.combatden.net"
BUCKET = "combatden-assets"
REGION = "us-east-1"
PROJECT_TAG = "combatden-assets"
# Squarespace (and most DNS hosts) auto-append the base domain to the Host field,
# so DNS records must use the host-RELATIVE name, never the FQDN.
BASE_DOMAIN = "combatden.net"

DEPLOY_DIR = Path(__file__).resolve().parent
STATE_FILE = DEPLOY_DIR / ".deploy-state.json"


def squarespace_host(fqdn: str) -> str:
    """An FQDN as a Squarespace DNS Host value: strip the trailing dot and the
    base domain (Squarespace appends `<base domain>` itself). ACM returns
    validation names like `_hash.cdn.combatden.net.`; this yields `_hash.cdn`.
    The apex domain itself becomes `@`."""
    name = fqdn.rstrip(".")
    if name == BASE_DOMAIN:
        return "@"
    suffix = "." + BASE_DOMAIN
    return name[: -len(suffix)] if name.endswith(suffix) else name


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    return json.loads(STATE_FILE.read_text())


def save_state(**kwargs) -> dict:
    state = load_state()
    state.update(kwargs)
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True))
    return state
