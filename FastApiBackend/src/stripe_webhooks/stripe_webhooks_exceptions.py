"""Exceptions for the Stripe webhooks domain."""


class WebhookRetryableError(Exception):
    """A webhook can't be processed yet but should be retried.

    Raised when a handler depends on state a related event/flow hasn't
    committed yet (a DB-first write race). The router acknowledges the
    webhook (200) and schedules a background retry so the event is
    reprocessed once the awaited row is visible.
    """


class SubscriptionItemPendingError(WebhookRetryableError):
    """Invoice lines reference subscription items not yet visible in the DB.

    Raised when an invoice contains ``subscription_item`` references but
    none match a ``member_memberships`` row.  This typically indicates a
    race condition: the webhook arrived before the create-flow committed
    the ``stripe_item_id`` column.

    The caller should acknowledge the webhook (200) and schedule a
    background retry so the event can be processed once the row is
    visible.
    """

    def __init__(
        self,
        stripe_invoice_id: str,
        gym_id: str,
        subscription_item_ids: list[str],
    ) -> None:
        self.stripe_invoice_id = stripe_invoice_id
        self.gym_id = gym_id
        self.subscription_item_ids = subscription_item_ids
        super().__init__(
            f"No membership matched subscription items "
            f"{subscription_item_ids} "
            f"(stripe_invoice_id={stripe_invoice_id}, gym_id={gym_id})"
        )


class InvoiceNotYetRecordedError(WebhookRetryableError):
    """An invoice payment arrived before its invoice row was recorded.

    ``invoice_payment.paid`` can be delivered (or processed) before the
    ``invoice.paid`` event that writes the ``member_invoices`` row the
    charge must reference. Retry until the invoice row exists.
    """

    def __init__(self, stripe_invoice_id: str, gym_id: str) -> None:
        self.stripe_invoice_id = stripe_invoice_id
        self.gym_id = gym_id
        super().__init__(
            f"Invoice not yet recorded for payment "
            f"(stripe_invoice_id={stripe_invoice_id}, gym_id={gym_id})"
        )
