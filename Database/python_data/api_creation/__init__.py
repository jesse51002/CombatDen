"""Backend-driven seed creation.

Every Stripe-backed row (membership plans + prices, discounts, members,
memberships) is created by POSTing to the FastAPI backend, so each row ends
up with a real test-mode Stripe ID. The overdue-member path talks to Stripe
directly (test clocks) — see overdue_members + stripe_direct.
"""
