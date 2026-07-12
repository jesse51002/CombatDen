"""Deterministic values produced by the data seed (single source of truth).

The seed (``Database/python_data``) is deterministic: ``SEED = 42`` and
``NUM_GYMS = 1`` (``Database/python_data/constants.py``). It provisions exactly
ONE gym, whose id comes from ``make_seeded_uuids(seed=3, count=1)[0]``
(``Database/python_data/utils.py``) and whose owner is ``owner1@test.com``
(``bootstrap/gyms.py`` → ``owner{i+1}@test.com`` with i=0).

Access is granted purely by a verified Supabase auth account whose email
matches a ``gym_employees`` row's email (compared lowercase) — there is no
``user_id`` FK. The seeded gym also carries one deterministic, real-login
employee per remaining role (``bootstrap/gyms.py``): an ``admin``
(``admin1@test.com``), a ``front_desk`` (``frontdesk1@test.com``), and a
``trainer`` (``trainer1@test.com``), all sharing the same seeded password.
A fourth staff row, ``pending-trainer1@test.com``, is a ``trainer`` with NO
verified auth account (legacy instructor data / the "pending" state) — do
not add a password constant for it, there is nothing to log in with.

Integration tests always target this one seeded gym — they never create gyms.
If the seed's gym-id derivation ever changes, update the value here (the one
place), rather than re-discovering a stale literal scattered across tests.
"""

SEEDED_GYM_ID = "21636369-8b52-9b4a-97b7-50923ceb3ffd"
SEEDED_OWNER_EMAIL = "owner1@test.com"
SEEDED_OWNER_PASSWORD = "abcd1234"
SEEDED_ADMIN_EMAIL = "admin1@test.com"
SEEDED_FRONT_DESK_EMAIL = "frontdesk1@test.com"
SEEDED_TRAINER_EMAIL = "trainer1@test.com"
