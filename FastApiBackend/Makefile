.PHONY: run dev lint format token

run:
	poetry run uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload

format:
	poetry run ruff check --fix src/
	poetry run ruff format src/

token:
	poetry run python scripts/generate_token.py --user-id $(user_id)
