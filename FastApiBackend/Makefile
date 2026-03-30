.PHONY: run dev lint format

run:
	poetry run uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload

format:
	poetry run ruff check --fix src/
	poetry run ruff format src/
