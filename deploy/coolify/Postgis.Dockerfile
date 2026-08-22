FROM postgres:16-bookworm

# A imagem oficial postgis/postgis:16-3.4 é somente amd64. O servidor do
# Web Lab é ARM64, então instalamos os pacotes oficiais sobre PostgreSQL
# multi-arquitetura.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-16-postgis-3 \
        postgresql-16-postgis-3-scripts \
    && rm -rf /var/lib/apt/lists/*
