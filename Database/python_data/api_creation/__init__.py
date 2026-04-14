"""Seeding modules that create entities via the FastAPI backend.

Each module in this package POSTs to a real backend endpoint and returns
lookup maps keyed by stable local handles (e.g. "gym0/plan2"). The real
server-generated IDs flow out through those lookups and get threaded into
downstream direct-DB generators (historical memberships, invoices, etc.).
"""
