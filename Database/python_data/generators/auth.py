from supabase import Client

from constants import DEFAULT_PASSWORD


def create_user(client: Client, email: str) -> dict:
    resp = client.auth.admin.create_user(
        {"email": email, "password": DEFAULT_PASSWORD, "email_confirm": True}
    )
    return {"id": resp.user.id, "email": resp.user.email}
