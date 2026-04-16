"""HTTP client for talking to the FastAPI backend during seeding.

Each gym has its own client instance holding that gym owner's JWT. The client
exposes small convenience helpers for the few endpoints the seeder uses so
callers don't have to juggle URLs and auth headers.
"""

from __future__ import annotations

from typing import Any

import httpx
from config import BACKEND_URL, fetch_access_token


class BackendError(RuntimeError):
    """Raised when a backend call returns a non-2xx status."""

    def __init__(self, method: str, path: str, status_code: int, body: str) -> None:
        super().__init__(f"{method} {path} -> {status_code}: {body[:500]}")
        self.method = method
        self.path = path
        self.status_code = status_code
        self.body = body


class GymApiClient:
    """Authenticated httpx client for a single gym owner.

    Wraps an `httpx.Client` (sync — matches the rest of the seed script) with
    a pre-set bearer token and a helper that raises a descriptive error on
    non-2xx responses.
    """

    def __init__(self, access_token: str, base_url: str = BACKEND_URL) -> None:
        self._client = httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=60.0,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> GymApiClient:
        return self

    def __exit__(self, *args: Any) -> None:
        self.close()

    def post(self, path: str, json: dict | None = None) -> dict | None:
        resp = self._client.post(path, json=json)
        return self._handle(resp, "POST", path)

    def delete(self, path: str, params: dict | None = None) -> dict | None:
        resp = self._client.delete(path, params=params)
        return self._handle(resp, "DELETE", path)

    def put(self, path: str, json: dict | None = None) -> dict | None:
        resp = self._client.put(path, json=json)
        return self._handle(resp, "PUT", path)

    @staticmethod
    def _handle(resp: httpx.Response, method: str, path: str) -> dict | None:
        if resp.status_code >= 400:
            raise BackendError(method, path, resp.status_code, resp.text)
        if resp.status_code == 204 or not resp.content:
            return None
        return resp.json()


def login_gym_owner(email: str, password: str) -> GymApiClient:
    """Sign in as a gym owner and return an authenticated client."""
    token = fetch_access_token(email, password)
    return GymApiClient(access_token=token)


def assert_backend_reachable() -> None:
    """Pre-flight: verify the backend is running before we start seeding."""
    try:
        resp = httpx.get(f"{BACKEND_URL}/health", timeout=5.0)
    except httpx.HTTPError as e:
        raise RuntimeError(
            f"Backend at {BACKEND_URL} is not reachable. Start it with "
            f"`make run` in the FastApiBackend dir. ({e})"
        ) from e
    if resp.status_code != 200:
        raise RuntimeError(f"Backend /health returned {resp.status_code}. Expected 200.")
