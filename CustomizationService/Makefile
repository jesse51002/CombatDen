.PHONY: litellm run smoke test

litellm:
	poetry run litellm --config litellm.config.yaml --port 4000

run:
	poetry run python -m src --app-yaml apps/combatden/app.yaml --customization-yaml apps/combatden/customization.yaml

smoke:
	poetry run python -m src --app-yaml apps/smoketest/app.yaml --customization-yaml apps/smoketest/customization.yaml

test:
	poetry run pytest tests/ -v
