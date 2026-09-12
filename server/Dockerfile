FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY server/pyproject.toml server/uv.lock* ./
RUN uv sync --frozen --no-dev --no-install-project 2>/dev/null || uv sync --no-dev --no-install-project

COPY server/app ./app
COPY data /data
COPY arena /arena

ENV USDA_SQLITE_PATH=/data/usda.sqlite
ENV FOODS_YAML_PATH=/data/foods.yaml
ENV ARENA_HTML_PATH=/arena/index.html
ENV UPLOAD_DIR=/app/uploads
ENV SQLITE_PATH=/app/mealee.sqlite
ENV PORT=8000

CMD ["sh", "-c", "uv run uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
