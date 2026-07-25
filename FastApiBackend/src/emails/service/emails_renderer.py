"""Jinja2 rendering of the three files that make up one email."""

import logging
from typing import Any

from jinja2 import Environment, FileSystemLoader, select_autoescape

from src.emails import TEMPLATES_DIR
from src.emails.emails_registry import SPECS
from src.emails.schema.emails_schema import (
    RenderedEmail,
    ResolvedRecipient,
)

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind  # isort: skip

logger = logging.getLogger(__name__)

SUBJECT_SUFFIX = ".subject.txt"
HTML_SUFFIX = ".html"
TEXT_SUFFIX = ".txt"


class EmailsRenderer:
    """Renders ``<template>.subject.txt`` / ``.html`` / ``.txt``.

    Autoescaping is ON for the HTML template: every value in the context is
    person- or gym-supplied (a gym name, a first name), so an unescaped
    render would put arbitrary input into a document we send from our own
    sending domain. The plain-text and subject templates are rendered with
    escaping OFF (there is no markup to escape, and an escaped ampersand in
    a subject line is a visible bug) — ``select_autoescape`` keys that off
    the filename.
    """

    def __init__(self) -> None:
        self._env = Environment(
            loader=FileSystemLoader(str(TEMPLATES_DIR)),
            autoescape=select_autoescape(
                enabled_extensions=("html",),
                default_for_string=False,
                default=False,
            ),
            trim_blocks=True,
            lstrip_blocks=True,
        )

    def render(
        self,
        payload: dict[str, Any],
        recipient: ResolvedRecipient,
        unsubscribe_url: str | None = None,
    ) -> RenderedEmail:
        """Render one email.

        Args:
            payload: The stored payload (its ``kind`` selects the spec).
            recipient: The resolved address + gym branding.
            unsubscribe_url: Required by every ``marketing`` kind's
                template; None for transactional kinds, which carry no
                unsubscribe link on purpose.

        Returns:
            The rendered subject, HTML body, and plain-text body.
        """
        kind = EmailKind(payload["kind"])
        template = SPECS[kind].template
        context = {
            "first_name": recipient.first_name,
            "gym_name": recipient.gym_name,
            "logo_url": recipient.logo_url,
            "unsubscribe_url": unsubscribe_url,
        }
        subject = self._env.get_template(
            f"{template}{SUBJECT_SUFFIX}"
        ).render(context)
        html = self._env.get_template(f"{template}{HTML_SUFFIX}").render(
            context
        )
        text = self._env.get_template(f"{template}{TEXT_SUFFIX}").render(
            context
        )
        # A trailing newline in a subject line is a header injection hazard
        # and renders as trailing whitespace; the file always ends with one.
        return RenderedEmail(
            subject=subject.strip(),
            html=html,
            text=text,
        )
