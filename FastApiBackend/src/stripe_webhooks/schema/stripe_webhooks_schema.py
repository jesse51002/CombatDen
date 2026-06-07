"""Schemas for the Stripe webhooks domain."""

from pydantic import BaseModel


class StripeWebhookAck(BaseModel):
    """Acknowledgement response for a received webhook."""

    received: bool = True
