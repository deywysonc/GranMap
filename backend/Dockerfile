FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /opt/granmap/backend

COPY backend/requirements.txt backend/requirements-production.txt ./
RUN pip install --upgrade pip && pip install -r requirements-production.txt

COPY backend/ ./
COPY app/assets/maps/gran_tiete_user_corrected_v10.json /opt/granmap/app/assets/maps/gran_tiete_user_corrected_v10.json

RUN addgroup --system granmap && adduser --system --ingroup granmap granmap \
    && chown -R granmap:granmap /opt/granmap
USER granmap

EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers"]
