# GranMap Backend

API de dados oficiais, mapa operacional, conta pessoal e inteligência
comunitária. SQLite é o caminho rápido de desenvolvimento; produção usa
PostgreSQL/PostGIS e Alembic.

## Executar

```powershell
cd C:\GranMap\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python seed.py
uvicorn main:app --reload
```

Abra:

- API: `http://127.0.0.1:8000`
- Swagger: `http://127.0.0.1:8000/docs`

## Primeiro administrador

1. Cadastre a conta pelo app ou por `POST /auth/register`.
2. Promova-a localmente:

```powershell
python promote_user.py seu@email.com admin
```

Papéis aceitos: `student`, `professor`, `moderator`, `coordination` e
`admin`. Somente coordenação/admin alteram dados acadêmicos; moderação,
coordenação e admin revisam propostas e leem auditoria.

## Testes

```powershell
python -m unittest discover -p "test_*.py" -v
```

Os testes usam bancos temporários e não alteram `granmap.db`.

## Produção

```bash
pip install -r requirements-production.txt
export GRANMAP_DATABASE_URL=postgresql://...
alembic upgrade head
uvicorn main:app --host 0.0.0.0
```

Em produção a API recusa iniciar sem PostgreSQL, cookie seguro e origens CORS
explícitas. `/metrics` expõe contadores e latência para Prometheus.
