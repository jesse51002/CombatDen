from supabase import Client

from constants import DEFAULT_PASSWORD


def create_user(client: Client, email: str, user_id=None) -> dict:
    payload = {"email": email, "password": DEFAULT_PASSWORD, "email_confirm": True}
    if user_id is not None:
        payload["id"] = str(user_id)
    resp = client.auth.admin.create_user(payload)
    return {"id": resp.user.id, "email": resp.user.email}
