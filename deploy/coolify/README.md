# Implantação do GranMap no Coolify/Web Lab

O servidor disponível é ARM64, com 2 CPUs e 3,7 GB de RAM, e compartilha
recursos com outros projetos. Use `compose.coolify.yaml`, que deixa o Docker
alocar CPU e memória conforme a demanda real do GranMap, sem publicar
PostgreSQL ou FastAPI diretamente.

## Recurso no Coolify

1. Projeto `Gran Map` → ambiente `production` → `+ Add Resource`.
2. Escolha repositório privado com Deploy Key, branch `main`.
3. Selecione build pack `Docker Compose`.
4. Informe `/compose.coolify.yaml` como arquivo Compose.
5. Configure como segredo `GRANMAP_POSTGRES_PASSWORD` com pelo menos 32 caracteres.
6. Configure `GRANMAP_PUBLIC_ORIGINS=https://granmap.weblab.dev.br`.
7. No primeiro deploy, mantenha `GRANMAP_ALLOW_REMOTE_DEMO_SEED=true` para criar
   as contas de apresentação. Depois altere para `false` e faça redeploy.

## Domínio

O proxy interno do Coolify está parado porque o host utiliza um proxy externo.
O serviço `admin` publica apenas `127.0.0.1:18180`. O responsável pelo servidor
deve criar o DNS `granmap.weblab.dev.br`, emitir TLS e encaminhar HTTPS para
`http://127.0.0.1:18180`.

O painel e a API ficam no mesmo domínio:

- painel: `https://granmap.weblab.dev.br/`;
- API: `https://granmap.weblab.dev.br/api/`;
- healthcheck: `https://granmap.weblab.dev.br/api/health`.

## Operação

- Banco persistente: volume `granmap-postgres-data`.
- Migrations: executadas pelo backend antes do Uvicorn.
- Retenção: crie uma tarefa agendada semanal no backend com `python retention.py`.
- Backup: agende backup do volume/banco antes de liberar usuários reais.
- Não inicie o proxy do Coolify sem autorização do responsável pelo servidor.
