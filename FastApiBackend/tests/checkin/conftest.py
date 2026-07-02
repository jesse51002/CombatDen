"""Fixtures for the checkin test suite.

The unit tests use the root ``tests/conftest.py`` fixtures (``client``,
``auth_headers``, ``db_pool_mock``, ``fake_member_id`` / ``fake_gym_id``). The
checkin **integration** tests (``test_checkin_integration.py`` /
``test_checkin_batch_integration.py``) drive the live running backend the same
way the suites under ``tests/integration/`` do, so we re-export the live client
fixtures (``api`` + its ``auth_token`` dependency) from the integration conftest
here — that registers them for this subtree.
"""

from tests.integration.conftest import (  # noqa: F401
    api,
    auth_token,
)
