import threading

from constants import DEFAULT_PASSWORD
from supabase import Client

# One lock per email address. The member fan-out runs concurrently AND several
# member rows legitimately share one email (the test member has three), so
# without this every worker clears GoTrue's "does this user exist" check before
# any of them has committed, and they collide on auth.users' unique index.
_email_locks: dict[str, threading.Lock] = {}
_email_locks_guard = threading.Lock()


def _lock_for(email: str) -> threading.Lock:
    with _email_locks_guard:
        return _email_locks.setdefault(email, threading.Lock())


def _find_existing(client: Client, email: str, user_id=None) -> dict | None:
    """The auth user for this email / id, or None when there isn't one."""
    if user_id is not None:
        try:
            existing = client.auth.admin.get_user_by_id(str(user_id))
        except Exception:
            return None
        return {"id": existing.user.id, "email": existing.user.email}
    # Admin list_users is paginated; page until we find it or run out.
    page = 1
    while True:
        users = client.auth.admin.list_users(page=page, per_page=200)
        if not users:
            return None
        for u in users:
            if u.email == email:
                return {"id": u.id, "email": u.email}
        if len(users) < 200:
            return None
        page += 1


def create_user(client: Client, email: str, user_id=None) -> dict:
    """Create an auth user, or return the existing row if one already exists.

    Re-running the seed would otherwise reinsert the same seeded UUIDs and
    explode on the "user already exists" error.

    On failure this asks whether the user EXISTS rather than parsing why the
    call failed. Matching the message text is not sound: GoTrue only returns a
    polite "already registered" error when the first create has COMMITTED. A
    concurrent duplicate instead reaches the Postgres unique index directly,
    and GoTrue reports that as a generic "Database error creating new user"
    (HTTP 500) which shares no wording with the polite version -- so a text
    match re-raises it and kills the whole seed. The state of the database is
    the reliable signal; the wording of the error is not.
    """
    payload = {"email": email, "password": DEFAULT_PASSWORD, "email_confirm": True}
    if user_id is not None:
        payload["id"] = str(user_id)
    with _lock_for(email):
        try:
            resp = client.auth.admin.create_user(payload)
            return {"id": resp.user.id, "email": resp.user.email}
        except Exception:
            existing = _find_existing(client, email, user_id)
            if existing is None:
                raise  # Nothing to reconcile against -- the failure was real.
            return existing
