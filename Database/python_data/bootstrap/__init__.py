"""Direct-DB seeding for all entities.

Everything writes to Supabase via the service-role client. There is no
backend round-trip — the product no longer handles payments, so no
Stripe-backed entities exist that would need to flow through the API.
"""
