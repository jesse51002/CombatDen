PORT ?= 4173

.PHONY: serve
serve:
	python3 serve.py $(PORT)

.PHONY: deploy-install deploy-provision deploy-finalize deploy-upload deploy
deploy-install:
	poetry install

deploy-provision:
	poetry run python deploy/provision.py

deploy-finalize:
	poetry run python deploy/finalize.py

deploy-upload:
	poetry run python deploy/upload.py

deploy: deploy-upload
