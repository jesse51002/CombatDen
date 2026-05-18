.PHONY: run smoke api test test-golden

run:
	poetry run python -m src --app-yaml apps/combatden/app.yaml --customization-yaml apps/combatden/customization.yaml

smoke:
	poetry run python -m src --app-yaml apps/smoketest/app.yaml --customization-yaml apps/smoketest/customization.yaml

api:
	poetry run uvicorn src.api.main:app --host 0.0.0.0 --port 8000 --reload

test:
	poetry run pytest tests/ -v -m "not golden"

# Live, paid: runs the cutout validator against the labeled golden corpus
# and prints a scorecard. Not part of `test`. `make test-golden ARGS="-k ..."`.
test-golden:
	poetry run pytest tests/test_cutout_golden.py -m golden -v -s $(ARGS)
