"""Exceptions for the Stripe webhooks domain."""


class SubscriptionItemPendingError(Exception):
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
