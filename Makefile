.PHONY: install dev seed test verify-foods usda spikes swift-test

install:
	cd server && uv sync

dev:
	cd server && uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

seed:
	cd server && uv run python -m app.seed

test:
	cd server && uv run pytest -q

usda:
	python3 data/build_usda.py

verify-foods:
	python3 data/build_usda.py --verify

spikes:
	python3 spikes/spike_battle.py
	cd server && uv run python ../spikes/spike_scale.py ../spikes/photos
	cd server && uv run python ../spikes/spike_seg.py ../spikes/photos
