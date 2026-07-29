.PHONY: run smoke api studio test sync-assets assets-install assets-provision assets-finalize docker-build ecr-push pause resume react-install react-dev react-build react-check

run:
	poetry run python -m src --app-yaml apps/combatden/app.yaml --customization-yaml apps/combatden/customization.yaml

smoke:
	poetry run python -m src --app-yaml apps/smoketest/app.yaml --customization-yaml apps/smoketest/customization.yaml

api:
	poetry run python -m uvicorn src.api.main:app --host 0.0.0.0 --port 8001 --reload

# The local launch surface (start a run, watch it stream). NOT deployed and
# NOT 0.0.0.0: it starts runs that spend real money, so it is bound to
# loopback only. Needs the full .env (it imports the pipeline).
studio:
	poetry run python -m uvicorn src.studio.main:app --host 127.0.0.1 --port 8002 --reload

test:
	poetry run pytest tests/ -v

# --- ThemeReact (the web theme runtime + standalone browser) ----------------
# npm, not poetry. ThemeReact/ is invisible to pyproject.toml and excluded from
# the API image (.dockerignore), exactly as ThemeFlutter/ is — the two sides
# share only the HTTP contract this Makefile's `api` target serves.
# `react-dev` serves on :8080 (pinned — see ThemeReact/vite.config.ts) and needs
# `make api` running alongside it.
react-install:
	cd ThemeReact && npm install

react-dev:
	cd ThemeReact && npm run dev

react-build:
	cd ThemeReact && npm run build

react-check:
	cd ThemeReact && npm run typecheck && npm run lint && npm run test

# Mirror all generated images/icons to S3 (backfill + repair). Needs boto3 + AWS
# creds; bucket defaults to combatden-assets. New runs self-upload via the Writer
# when ASSET_UPLOAD_ENABLED=1; this is the one-shot backfill (skips unchanged).
sync-assets:
	poetry run python -m scripts.sync_assets.run

# --- Asset CDN provisioning (combatden-assets + cdn.combatden.net) ----------
# One-time, own boto3-only venv in deploy-assets/ (no uvloop). See ../DEPLOYMENT.md.
assets-install:
	cd deploy-assets && poetry install
# Ensure the bucket + request the ACM cert; prints the validation CNAME.
assets-provision:
	cd deploy-assets && poetry run python provision.py
# After the cert validates: OAC + cache policy (keyed on ?v=) + CloudFront distro.
assets-finalize:
	cd deploy-assets && poetry run python finalize.py

# --- Production (AWS App Runner) — see ../DEPLOYMENT.md ---------------------
ECR ?= 259645229668.dkr.ecr.us-east-1.amazonaws.com/combatden-themeservice
SERVICE_ARN ?= arn:aws:apprunner:us-east-1:259645229668:service/combatden-themeservice/8db0e7b19c8b4a9d9c952489e84809e1

# Build the serving image (assets baked in; see Dockerfile + .dockerignore).
docker-build:
	docker build -t combatden-themeservice:latest .

# Build + push to ECR + trigger an App Runner deploy (AutoDeployments are off).
ecr-push: docker-build
	aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 259645229668.dkr.ecr.us-east-1.amazonaws.com
	docker tag combatden-themeservice:latest $(ECR):latest
	docker push $(ECR):latest
	aws apprunner start-deployment --region us-east-1 --service-arn $(SERVICE_ARN) --query 'OperationId' --output text

# Demo on/off: pause stops compute billing between demos; resume (~1 min) before.
pause:
	aws apprunner pause-service --region us-east-1 --service-arn $(SERVICE_ARN) --query 'Service.Status' --output text

resume:
	aws apprunner resume-service --region us-east-1 --service-arn $(SERVICE_ARN) --query 'Service.Status' --output text
