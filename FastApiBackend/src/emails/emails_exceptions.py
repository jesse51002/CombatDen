"""Custom exceptions for the emails domain.

All subclass ``ValueError`` so a generic ``except ValueError`` in a router
still catches an unmapped domain error as a 400 (bad input) rather than a
500 — mirrors ``src/employees/employees_exceptions.py``.
"""


class EmailsProviderError(ValueError):
    """The mail provider rejected the send (non-2xx or a transport error).

    Retryable: the ``email_log`` row stays ``failed`` and the reconciler's
    retry sweep picks it up again until the attempt ceiling.
    """


class EmailNotFoundError(ValueError):
    """No ``email_log`` row exists for the given ``email_id``.

    Router → 404.
    """


class ResendLimitExceededError(ValueError):
    """The per-subject, per-kind resend cap for the trailing window was hit.

    Router → 429.
    """


class EmailsUnsubscribeUnconfiguredError(ValueError):
    """No unsubscribe signing secret is set, so no marketing mail may go out.

    Raised by ``EmailsSuppression.mint_token``. An empty secret is not a weak
    key — HMAC accepts ``b""`` happily — so minting anyway would produce a
    token anyone could forge from the public algorithm. A marketing email
    whose opt-out link can be forged (or, worse, one that silently opts a
    stranger out) is worse than one that is not sent, so the send is recorded
    as failed and retried once the secret is configured.
    """
