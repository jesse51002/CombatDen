"""Unit tests for ``EmailsSuppression`` — signed tokens + the category gate.

No DB: the one suppression read is driven through a mocked ``db_pool``, and
the category asymmetry is asserted on the BOUND PARAMETERS rather than by
re-implementing ``sql/suppression_check.sql`` in the test. That file ANDs
``include_marketing`` with ``scope = 'marketing'``, so the flag is the whole
difference between "a pitch is blocked" and "the login link is blocked".
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.emails.emails_exceptions import (
    EmailsUnsubscribeUnconfiguredError,
)
from src.emails.emails_registry import EmailCategory
from src.emails.service.emails_suppression import (
    TOKEN_FIELD_SEPARATOR,
    TOKEN_PART_SEPARATOR,
    EmailsSuppression,
)

SECRET = "unit-test-unsubscribe-signing-secret"
OTHER_SECRET = "a-completely-different-signing-secret"

EMAIL = "ada@example.com"
VICTIM_EMAIL = "victim@example.com"


def _make(
    secret: str = SECRET,
    *,
    row: dict | None = None,
) -> tuple[EmailsSuppression, AsyncMock]:
    """An ``EmailsSuppression`` whose suppression read returns ``row``.

    Returns the service plus the session mock, so a test can assert on the
    parameters the query was actually bound with.
    """
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row

    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(return_value=result)

    db_pool = MagicMock()
    db_pool.session.return_value = session
    db_pool.execute_with_retry = AsyncMock()
    service = EmailsSuppression(db_pool=db_pool, unsubscribe_secret=secret)
    return service, session


# ── the signed token ──────────────────────────────────────────────


def test_token_round_trips_to_the_email_and_gym() -> None:
    """The link carries its own authorization, so it must decode exactly."""
    suppression, _ = _make()
    gym_id = uuid4()

    token = suppression.mint_token(EMAIL, gym_id)

    assert suppression.verify_token(token) == (EMAIL, gym_id)


def test_mint_lowercases_the_email() -> None:
    """Addresses are matched case-insensitively everywhere else (the SQL
    lowercases both sides), so the token must not preserve the casing a
    template happened to render with."""
    suppression, _ = _make()
    gym_id = uuid4()

    token = suppression.mint_token("Ada@Example.COM", gym_id)

    assert suppression.verify_token(token) == (EMAIL, gym_id)


def test_a_body_swapped_onto_another_signature_does_not_verify() -> None:
    """The attack the signature exists to stop: unsubscribing someone else.

    Both tokens are genuine, so this is not a malformed-input check — it is
    the proof that the signature covers the body it is attached to.
    """
    suppression, _ = _make()
    gym_id = uuid4()
    mine = suppression.mint_token(EMAIL, gym_id)
    theirs = suppression.mint_token(VICTIM_EMAIL, gym_id)

    my_signature = mine.partition(TOKEN_PART_SEPARATOR)[2]
    their_body = theirs.partition(TOKEN_PART_SEPARATOR)[0]
    forged = f"{their_body}{TOKEN_PART_SEPARATOR}{my_signature}"

    assert suppression.verify_token(forged) is None


@pytest.mark.parametrize(
    "token",
    [
        "totally-made-up.0123456789abcdef0123456789abcdef",
        "no-separator-in-here-at-all",
        "",
        TOKEN_PART_SEPARATOR,
    ],
    ids=["garbage", "no_separator", "empty", "separator_only"],
)
def test_malformed_tokens_do_not_verify(token: str) -> None:
    """Every failure mode returns None, so the caller can answer them all
    identically and a prober learns nothing from the difference."""
    suppression, _ = _make()

    assert suppression.verify_token(token) is None


def test_a_token_signed_with_another_secret_does_not_verify() -> None:
    """A token is only good against the key that minted it."""
    other, _ = _make(OTHER_SECRET)
    ours, _ = _make(SECRET)

    assert ours.verify_token(other.mint_token(EMAIL, uuid4())) is None


def test_an_empty_secret_fails_closed_in_both_directions() -> None:
    """The security guard: no key means no signing AND no verifying.

    HMAC accepts a ``b""`` key perfectly happily, so without the explicit
    ``signing_enabled`` guard an unset secret would mint tokens anyone could
    forge from the public algorithm — and verify those forgeries too, which
    is one link away from unsubscribing any address at any gym.

    The token built below is correctly signed under the empty key: a
    configured instance accepts the identical construction (asserted first,
    so the forgery is proven to be a real token shape rather than junk), and
    the unconfigured one still refuses it.
    """
    configured, _ = _make(SECRET)
    unconfigured, _ = _make("")
    gym_id = uuid4()
    body = EmailsSuppression._encode(
        f"{VICTIM_EMAIL}{TOKEN_FIELD_SEPARATOR}{gym_id}"
    )

    valid = f"{body}{TOKEN_PART_SEPARATOR}{configured._sign(body)}"
    assert configured.verify_token(valid) == (VICTIM_EMAIL, gym_id)

    assert configured.signing_enabled is True
    assert unconfigured.signing_enabled is False
    with pytest.raises(EmailsUnsubscribeUnconfiguredError):
        unconfigured.mint_token(EMAIL, gym_id)

    forged = f"{body}{TOKEN_PART_SEPARATOR}{unconfigured._sign(body)}"
    assert unconfigured.verify_token(forged) is None
    assert unconfigured.verify_token(valid) is None


# ── the category gate ─────────────────────────────────────────────


@pytest.mark.parametrize(
    ("category", "include_marketing"),
    [
        (EmailCategory.marketing, True),
        (EmailCategory.transactional, False),
    ],
    ids=["marketing", "transactional"],
)
@pytest.mark.asyncio
async def test_include_marketing_follows_the_kind_category(
    category: EmailCategory,
    include_marketing: bool,
) -> None:
    """The asymmetry that keeps an unsubscribe from locking someone out.

    ``suppression_check.sql`` only considers a ``marketing`` suppression row
    when this flag is true, so a transactional kind stays deliverable to an
    address that opted out of pitches — and only an ``all`` suppression
    blocks it.
    """
    suppression, session = _make()
    gym_id = uuid4()

    await suppression.is_suppressed(EMAIL, gym_id, category)

    params = session.execute.await_args.args[1]
    assert params["include_marketing"] is include_marketing
    assert params["email"] == EMAIL
    assert params["gym_id"] == str(gym_id)


@pytest.mark.parametrize(
    ("row", "expected"),
    [({"suppressed": 1}, True), (None, False)],
    ids=["row_found", "no_row"],
)
@pytest.mark.asyncio
async def test_is_suppressed_reports_whether_a_row_matched(
    row: dict | None,
    expected: bool,
) -> None:
    """The query returns at most one marker row; its presence IS the answer."""
    suppression, _ = _make(row=row)

    result = await suppression.is_suppressed(
        EMAIL, uuid4(), EmailCategory.marketing
    )

    assert result is expected
