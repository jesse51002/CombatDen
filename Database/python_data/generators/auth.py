from constants import DEFAULT_PASSWORD
from supabase import Client


def create_user(client: Client, email: str, user_id=None) -> dict:
    """Create an auth user, or return the existing row if one already exists.

    Re-running the seed script was reinserting the same seeded UUIDs and
    exploding on the "user already exists" error. We catch it and look the
    user up by id instead.
    """
    payload = {"email": email, "password": DEFAULT_PASSWORD, "email_confirm": True}
    if user_id is not None:
        payload["id"] = str(user_id)
    try:
        resp = client.auth.admin.create_user(payload)
        return {"id": resp.user.id, "email": resp.user.email}
    except Exception as exc:
        msg = str(exc).lower()
        if "already" not in msg and "exist" not in msg and "registered" not in msg:
            raise
        if user_id is not None:
            existing = client.auth.admin.get_user_by_id(str(user_id))
            return {"id": existing.user.id, "email": existing.user.email}
        # Fallback: list users and match by email. Admin list_users is
        # paginated; we page until we find it.
        page = 1
        while True:
            users = client.auth.admin.list_users(page=page, per_page=200)
            if not users:
                raise
            for u in users:
                if u.email == email:
                    return {"id": u.id, "email": u.email}
            if len(users) < 200:
                raise
            page += 1
