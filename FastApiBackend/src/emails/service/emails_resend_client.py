"""Thin HTTP client for the Resend send API."""

import logging

import httpx

from src.emails.emails_exceptions import EmailsProviderError
from src.emails.schema.emails_schema import RenderedEmail

logger = logging.getLogger(__name__)

RESEND_SEND_URL = "https://api.resend.com/emails"
REQUEST_TIMEOUT_SECONDS = 30.0


class EmailsResendClient:
    """POSTs one rendered message to Resend and returns its message id."""

    def __init__(
        self,
        api_key: str,
        from_address: str,
        from_name: str,
        reply_to: str | None = None,
        sandbox_redirect: str | None = None,
    ) -> None:
        self._api_key = api_key
        self._from_address = from_address
        self._from_name = from_name
        self._reply_to = reply_to
        # Non-prod safety valve: when set, EVERY message goes to this address
        # instead of the real recipient, so a dev run against real data can
        # never mail a real gym's staff or members.
        self._sandbox_redirect = sandbox_redirect

    async def send(
        self,
        recipient: str,
        message: RenderedEmail,
    ) -> str | None:
        """Send one message.

        Args:
            recipient: The resolved address (overridden by the sandbox
                redirect when one is configured).
            message: The rendered subject / html / text.

        Returns:
            The provider's message id, or None when the response carries
            none (a 2xx is still a successful send).

        Raises:
            EmailsProviderError: On a non-2xx response or a transport
                failure. Retryable — the caller marks the row ``failed``.
        """
        body = {
            "from": f"{self._from_name} <{self._from_address}>",
            "to": [self._sandbox_redirect or recipient],
            "subject": message.subject,
            "html": message.html,
            "text": message.text,
        }
        if self._reply_to:
            body["reply_to"] = self._reply_to

        try:
            async with httpx.AsyncClient(
                timeout=REQUEST_TIMEOUT_SECONDS
            ) as client:
                response = await client.post(
                    RESEND_SEND_URL,
                    json=body,
                    headers={
                        "Authorization": f"Bearer {self._api_key}",
                        "Content-Type": "application/json",
                    },
                )
        except httpx.HTTPError as exc:
            raise EmailsProviderError(f"Resend request failed: {exc}") from exc

        if response.status_code >= httpx.codes.BAD_REQUEST:
            raise EmailsProviderError(
                f"Resend rejected the send ({response.status_code}): "
                f"{response.text[:500]}"
            )

        return self._message_id(response)

    @staticmethod
    def _message_id(response: httpx.Response) -> str | None:
        """Pull the provider message id out of a 2xx response body."""
        try:
            data = response.json()
        except ValueError:
            return None
        raw = data.get("id") if isinstance(data, dict) else None
        return str(raw) if raw else None
