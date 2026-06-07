"""API routes for the Stripe webhooks domain."""

import logging

import stripe
from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status

from src.core.config import settings
from src.core.dependencies import DependencyInjector
from src.stripe_webhooks.schema.stripe_webhooks_schema import StripeWebhookAck
from src.stripe_webhooks.service.stripe_webhooks_service import (
    StripeWebhooksService,
)
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    SubscriptionItemPendingError,
)

logger = logging.getLogger(__name__)

stripe_webhooks_router = APIRouter(
    prefix="/api/v1/stripe",
    tags=["stripe-webhooks"],
)


@stripe_webhooks_router.post(
    "/webhooks",
    response_model=StripeWebhookAck,
    status_code=status.HTTP_200_OK,
    summary="Receive Stripe Connect webhook",
    description=(
        "Receives Stripe Connect webhook events. The endpoint is "
        "unauthenticated at the HTTP layer — Stripe is authenticated "
        "via the Stripe-Signature header, verified against "
        "``stripe_connect_webhook_secret``."
    ),
    responses={
        200: {"description": "Event received (or deduplicated)"},
        400: {"description": "Invalid or missing Stripe signature"},
        500: {"description": "Handler failed — Stripe should retry"},
    },
)
@inject
async def receive_stripe_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    service: StripeWebhooksService = Depends(Provide[DependencyInjector.stripe_webhooks_service]),
) -> StripeWebhookAck:
    """Verify a Stripe webhook signature and dispatch it to a handler.

    Stripe retries aggressively on 5xx, so handler failures must be
    genuinely retriable. Every handler is idempotent via the outer
    ``stripe_webhook_events`` log + inner UNIQUE constraints.
    """
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")

    if not sig_header:
        logger.warning("Stripe webhook missing Stripe-Signature header")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Stripe-Signature header",
        )

    try:
        event = stripe.Webhook.construct_event(
            payload=payload,
            sig_header=sig_header,
            secret=settings.stripe_connect_webhook_secret,
        )
    except stripe.SignatureVerificationError:
        logger.warning("Stripe webhook signature verification failed")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Stripe signature",
        ) from None
    except ValueError:
        logger.warning("Stripe webhook has an invalid payload")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook payload",
        ) from None

    # ``construct_event`` returns a ``stripe.Event`` whose ``to_dict()``
    # gives a plain dict that handlers can treat as JSON.
    event_dict = event.to_dict() if hasattr(event, "to_dict") else dict(event)

    try:
        await service.handle_event(event_dict)
    except SubscriptionItemPendingError:
        logger.warning(
            "Stripe webhook deferred to background retry "
            "(subscription item not yet visible): "
            "event_id=%s event_type=%s",
            event_dict.get("id"),
            event_dict.get("type"),
        )
        background_tasks.add_task(service.retry_pending_event, event_dict)
        return StripeWebhookAck(received=True)
    except Exception:
        logger.error(
            "Stripe webhook handler failed: event_id=%s event_type=%s",
            event_dict.get("id"),
            event_dict.get("type"),
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Webhook handler failed",
        ) from None

    return StripeWebhookAck(received=True)
