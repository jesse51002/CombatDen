"""Unit tests for ``EmailsRenderer`` — the REAL templates, no DB, no provider.

Every test renders from the actual files in ``src/emails/templates/``, so a
kind added to ``SPECS`` without its three template files fails here rather
than at send time, in front of a member.

Two rules the renderer exists to enforce are locked down:

* **HTML escapes, plaintext does not.** A gym name is user input landing in a
  document we send from our own sending domain, so the ``.html`` part must
  escape it — but escaping the ``.txt`` or subject part would put a literal
  ``&amp;`` in front of a member, which is a visible bug, not safety.
* **Marketing carries an opt-out, transactional never mentions one.** Opting
  out of a pitch must not cost someone the link that gets them into the
  product, so the transactional template has no unsubscribe line at all.
"""

import html as html_lib

import pytest

from src.emails.emails_registry import SPECS, EmailCategory
from src.emails.schema.emails_schema import ResolvedRecipient
from src.emails.service.emails_renderer import EmailsRenderer

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind  # isort: skip

# A gym name that is also markup. Every part of the render sees the same
# string, so one input proves both halves of the escaping rule.
GYM_NAME_WITH_MARKUP = "Rock & Roll <BJJ>"

# No ``&``/``<``/``>`` in it on purpose: the URL must survive HTML escaping
# byte-for-byte, so a mismatch means the template dropped it, not that Jinja
# rewrote it.
UNSUBSCRIBE_URL = (
    "https://api.combatden.net/api/v1/emails/unsubscribe?token=abc123"
)

ALL_KINDS = sorted(SPECS)
MARKETING_KINDS = sorted(
    kind
    for kind, spec in SPECS.items()
    if spec.category is EmailCategory.marketing
)
TRANSACTIONAL_KINDS = sorted(
    kind
    for kind, spec in SPECS.items()
    if spec.category is EmailCategory.transactional
)


def _recipient(gym_name: str = "Iron Fist BJJ") -> ResolvedRecipient:
    """A resolved recipient with branding, as ``EmailsRecipients`` returns."""
    return ResolvedRecipient(
        email="ada@example.com",
        first_name="Ada",
        gym_name=gym_name,
        logo_url="https://cdn.combatden.net/logo.png",
    )


def _payload(kind: EmailKind) -> dict[str, str]:
    """The stored payload as ``_deliver`` hands it over — ``kind`` selects
    the spec, and nothing else in it reaches the template context."""
    return {"kind": str(kind)}


@pytest.mark.parametrize("kind", ALL_KINDS, ids=str)
def test_every_registered_kind_renders_all_three_parts(
    kind: EmailKind,
) -> None:
    """A kind in ``SPECS`` must have all three template files on disk.

    Parametrized over the registry rather than a hardcoded list so adding a
    kind without its ``.subject.txt`` / ``.html`` / ``.txt`` files fails
    loudly here instead of raising ``TemplateNotFound`` mid-send.
    """
    message = EmailsRenderer().render(
        _payload(kind), _recipient(), unsubscribe_url=UNSUBSCRIBE_URL
    )

    assert message.subject.strip()
    assert message.html.strip()
    assert message.text.strip()
    # A trailing newline in a subject is a header-injection hazard; the
    # template file always ends with one, so the renderer must strip it.
    assert message.subject == message.subject.strip()


@pytest.mark.parametrize("kind", ALL_KINDS, ids=str)
def test_gym_name_is_escaped_in_html_and_left_raw_elsewhere(
    kind: EmailKind,
) -> None:
    """Autoescape is scoped to ``.html`` by extension, deliberately.

    The HTML part must not carry raw ``<``/``&`` from a gym's own name; the
    plaintext and subject parts must not carry entity escapes, because there
    is no markup there to escape and ``&amp;`` in a subject line is visible.
    """
    message = EmailsRenderer().render(
        _payload(kind),
        _recipient(GYM_NAME_WITH_MARKUP),
        unsubscribe_url=UNSUBSCRIBE_URL,
    )

    assert html_lib.escape(GYM_NAME_WITH_MARKUP) in message.html
    assert GYM_NAME_WITH_MARKUP not in message.html

    assert GYM_NAME_WITH_MARKUP in message.text
    assert GYM_NAME_WITH_MARKUP in message.subject
    assert "&amp;" not in message.text
    assert "&amp;" not in message.subject


@pytest.mark.parametrize("kind", MARKETING_KINDS, ids=str)
def test_marketing_templates_carry_the_unsubscribe_url(
    kind: EmailKind,
) -> None:
    """A marketing kind is a pitch, so the opt-out link is mandatory.

    Both bodies must carry it — a recipient reading the plaintext part has
    the same right to leave as one reading the HTML.
    """
    message = EmailsRenderer().render(
        _payload(kind), _recipient(), unsubscribe_url=UNSUBSCRIBE_URL
    )

    assert UNSUBSCRIBE_URL in message.html
    assert UNSUBSCRIBE_URL in message.text


@pytest.mark.parametrize("kind", TRANSACTIONAL_KINDS, ids=str)
def test_transactional_templates_reference_no_unsubscribe_url(
    kind: EmailKind,
) -> None:
    """A transactional kind carries access, so it has no opt-out line.

    A URL is passed in anyway: if the template ever grew an unsubscribe
    reference it would surface here, whereas the production call site passes
    None and a stray reference would only render the string "None".
    """
    message = EmailsRenderer().render(
        _payload(kind), _recipient(), unsubscribe_url=UNSUBSCRIBE_URL
    )

    assert UNSUBSCRIBE_URL not in message.html
    assert UNSUBSCRIBE_URL not in message.text
    assert "unsubscribe" not in message.html.lower()
    assert "unsubscribe" not in message.text.lower()
