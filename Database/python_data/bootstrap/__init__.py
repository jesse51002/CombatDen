"""Direct-DB seeding for entities without backend CREATE endpoints.

Everything in here writes to Supabase via the service-role client, because
the corresponding entities (gyms, gym_employees, gym_classes, gym_rewards,
gym_history) are admin-provisioned in production and have no REST endpoints
we can hit from the seed script. Stripe-backed entities go through the API
instead — see `api_creation/`.
"""
