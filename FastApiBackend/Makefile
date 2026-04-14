.PHONY: run dev lint format token webhook test test-payments test-members test-memberships test-plans test-discounts

run:
	poetry run uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload

format:
	poetry run ruff check --fix src/
	poetry run ruff format src/

token:
	poetry run python scripts/generate_token.py --email owner2@test.com --password abcd1234

webhook:
	stripe listen --forward-connect-to localhost:8000/api/v1/stripe/webhooks

test:
	poetry run pytest tests/ -v --tb=short

test-payments:
	poetry run pytest tests/payments/ -v --tb=short

test-members:
	poetry run pytest tests/members/ -v --tb=short

test-memberships:
	poetry run pytest tests/member_memberships/ -v --tb=short

test-plans:
	poetry run pytest tests/membership_plans/ -v --tb=short

test-discounts:
	poetry run pytest tests/discounts/ -v --tb=short
