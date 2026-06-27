"""HTTP client for talking to the FastAPI backend during seeding.

Each gym has its own client instance holding that gym owner's JWT. The client
exposes small convenience helpers for the few endpoints the seeder uses so
callers don't have to juggle URLs and auth headers.
"""

from __future__ import annotations

import time
from typing import Any

import httpx
import progress
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

    Wraps a sync `httpx.Client` with a pre-set bearer token and a helper that
    raises a descriptive error on non-2xx responses.
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
        return self._send("POST", path, json=json)

    def delete(
        self,
        path: str,
        params: dict | None = None,
        json: dict | None = None,
    ) -> dict | None:
        return self._send("DELETE", path, json=json, params=params)

    def put(self, path: str, json: dict | None = None) -> dict | None:
        return self._send("PUT", path, json=json)

    def _send(
        self,
        method: str,
        path: str,
        *,
        json: dict | None = None,
        params: dict | None = None,
    ) -> dict | None:
        """Issue one request, printing its method/path before and its status +
        elapsed after — so the seed shows every backend call live and a slow or
        hung call (e.g. a 60s ReadTimeout on a membership start) reports exactly
        which call it was and how long it ran before failing.
        """
        progress.log(f"    -> {method} {path}")
        start = time.perf_counter()
        try:
            resp = self._client.request(method, path, json=json, params=params)
        except Exception as exc:
            elapsed = time.perf_counter() - start
            progress.log(
                f"    FAIL {method} {path} after {elapsed:.2f}s "
                f"({type(exc).__name__})"
            )
            raise
        elapsed = time.perf_counter() - start
        marker = "OK  " if resp.status_code < 400 else "ERR "
        progress.log(
            f"    {marker} {resp.status_code} {method} {path}  ({elapsed:.2f}s)"
        )
        return self._handle(resp, method, path)

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
