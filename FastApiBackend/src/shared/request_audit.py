"""Capture signing-context audit fields (IP, user-agent) from a request.

The waiver e-signature audit columns (``member_waiver_signatures.ip_address`` /
``user_agent``) are NOT NULL, so capture coalesces a missing client host or
absent header to a sentinel rather than NULL. Used by every path that records a
signature (the standalone signing endpoint and the authorized-payer link flow).
"""

from fastapi import Request

UNKNOWN_IP = "0.0.0.0"
UNKNOWN_USER_AGENT = "unknown"


def capture_ip_address(request: Request) -> str:
    """Return the request client's IP, or a sentinel if unavailable."""
    return request.client.host if request.client else UNKNOWN_IP


def capture_user_agent(request: Request) -> str:
    """Return the request's User-Agent header, or a sentinel if absent."""
    return request.headers.get("user-agent") or UNKNOWN_USER_AGENT
