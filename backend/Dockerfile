FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /opt/granmap/backend

COPY backend/requirements.txt backend/requirements-production.txt ./
RUN pip install --upgrade pip && pip install -r requirements-production.txt

COPY backend/ ./
COPY app/assets/maps/gran_tiete_upper_floorplan_v11.json /opt/granmap/app/assets/maps/gran_tiete_upper_floorplan_v11.json

RUN addgroup --system granmap && adduser --system --ingroup granmap granmap \
    && chown -R granmap:granmap /opt/granmap
USER granmap

EXPOSE 8000
CMD ["sh", "-c", "if [ \"${GRANMAP_RUN_MIGRATIONS_ON_STARTUP:-true}\" = \"true\" ]; then alembic upgrade head; fi && if [ \"${GRANMAP_ALLOW_REMOTE_DEMO_SEED:-false}\" = \"true\" ]; then python seed_demo.py; fi && exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers"]
