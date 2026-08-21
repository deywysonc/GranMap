# GranMap na Oracle Cloud Always Free

Esta configuração publica a demo em uma única VM Ampere A1:

- `app.<ip>.sslip.io`: aplicativo Flutter Web e download do APK;
- `admin.<ip>.sslip.io`: GranMap Admin;
- `api.<ip>.sslip.io`: FastAPI;
- PostgreSQL/PostGIS acessível somente pela rede interna do Docker;
- HTTPS automático pelo Caddy.

## Limites de segurança

- escolha somente uma shape identificada como **Always Free-eligible**;
- mantenha `GRANMAP_COMMERCIAL_LAUNCH=false` enquanto faltarem dados institucionais;
- não exponha as portas 5432 ou 8000 na VCN;
- não versione `.env`, chaves SSH ou backups do banco;
- crie alertas de orçamento antes de usar qualquer recurso fora da franquia.

## Inicialização

Depois de copiar o repositório e os builds para `/opt/granmap`:

```bash
cd /opt/granmap
sudo ./deploy/oracle/bootstrap.sh
cp deploy/oracle/.env.example deploy/oracle/.env
# Edite hostnames, e-mail e senha antes de continuar.
docker compose --env-file deploy/oracle/.env \
  -f deploy/oracle/compose.yaml up -d --build
```

Confirme a implantação com:

```bash
docker compose --env-file deploy/oracle/.env \
  -f deploy/oracle/compose.yaml ps
curl -fsS "https://${GRANMAP_API_HOST}/health"
```
