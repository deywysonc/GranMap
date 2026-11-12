# GranMap

GranMap é uma plataforma de orientação indoor para a Faculdade Gran Tietê.
O mapa do térreo ainda é aproximado, e o piso superior usa a planta fornecida.
Essa base permite validar busca, rotas, troca de pisos, horários, conta pessoal
e avisos comunitários. Escala, distâncias e posicionamento indoor ainda
precisam de medição e calibração presencial.

## O que já funciona

- mapa dos pisos 0 e 1, com salas, laboratórios e pontos de interesse;
- busca, autocomplete e rotas A* compartilhadas por coordenadas X/Y/Z;
- navegação contínua no mapa 2D, maquete 3D e Gran Lens AR;
- planta com paredes, portas, corredores e seleção de locais por toque;
- câmera real opcional no Gran Lens e leitura de âncoras por QR;
- sensores físicos, fusão giroscópio/magnetômetro, detecção de passos, PDR e Map Matching;
- troca de piso, instruções, progresso, ETA conceitual e rota acessível;
- simulador de posição com Map Matching, telemetria e confiança visual;
- cadastro/login, perfil, horários, favoritos e histórico;
- botão para a próxima aula e integração entre grade e navegação;
- contribuições autenticadas, voto único editável, consenso e reputação;
- cache e fila offline atômicos para propostas e votos, isolados por conta e API;
- sincronização de pendências a cada 20 segundos com o app em primeiro plano;
- repetição segura com idempotência, retentativa exponencial e fila de falhas recuperável;
- SQLite local estruturado, credencial no Keychain/Keystore e mapa/grade/notificações em cache;
- onboarding, consentimento de localização, alto contraste e preferência de rota acessível persistentes;
- sessões revogáveis, troca/recuperação de senha, exportação e exclusão da conta;
- modo de manutenção, bloqueio de versões antigas e chaves de funcionalidades controladas pela API;
- diagnóstico seguro com identificador de requisição e relatório copiável, sem expor o token;
- notificações de alteração da grade, com leitura e cópia offline;
- notificações com limites de espera, nova tentativa e proteção na troca de conta;
- painel institucional com CRUD acadêmico, papéis, conflitos, moderação e auditoria;
- versões publicáveis do mapa, preview visual, bloqueios de Edge, recálculo e âncoras;
- coleta magnética versionada pelo GranMap Lab;
- FastAPI pronto para PostgreSQL/PostGIS, Alembic, containers, métricas e CI.

## Abrir a demo completa

Com as dependências instaladas, um único comando prepara um banco determinístico,
inicia API, Admin e aplicativo e abre o GranMap no navegador:

```powershell
cd C:\GranMap
.\scripts\start_demo.ps1
```

Endereços da apresentação:

- aplicativo: http://127.0.0.1:8088
- Admin: http://127.0.0.1:5174
- documentação da API: http://127.0.0.1:8100/docs

Contas prontas (senha `GranMap123!`):

- aluno: `aluno@granmap.demo`
- moderador: `moderador@granmap.demo`
- administrador: `admin@granmap.demo`

O cenário volta ao estado original em toda inicialização. Use
`.\scripts\start_demo.ps1 -NoReset` para preservar a sessão, ou execute
`.\scripts\reset_demo.ps1` e `.\scripts\stop_demo.ps1` separadamente.

Valide automaticamente a jornada e os quatro serviços com:

```powershell
.\scripts\verify_demo.ps1
```

O roteiro humano da apresentação está em
[docs/DEMO_ROTEIRO.md](docs/DEMO_ROTEIRO.md).

## Executar localmente

Em três terminais:

```powershell
cd C:\GranMap\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python seed.py
uvicorn main:app --reload
```

```powershell
cd C:\GranMap\admin_web
npm install
npm run dev
```

```powershell
cd C:\GranMap\app
flutter pub get
flutter run -d chrome --dart-define=GRANMAP_API_URL=http://127.0.0.1:8000
```

Crie uma conta no app e promova-a antes de entrar no Admin:

```powershell
cd C:\GranMap\backend
python promote_user.py seu@email.com admin
```

Consulte [PROJECT.md](PROJECT.md), [ARCHITECTURE.md](ARCHITECTURE.md) e
[docs/MAPA_CONCEITUAL_V6.md](docs/MAPA_CONCEITUAL_V6.md) antes de alterar o
modelo de navegação. O novo critério de conclusão está em
[docs/DEMO_VERTICAL_COMPLETA.md](docs/DEMO_VERTICAL_COMPLETA.md).

## Stack comercial em containers

O compose sobe PostgreSQL/PostGIS, aplica Alembic, inicia a API e publica o
Admin atrás de um proxy `/api`:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

Abra `http://localhost:8080`. O perfil padrão do compose é de desenvolvimento
local. Produção exige HTTPS externo, `GRANMAP_ENVIRONMENT=production`, cookie
seguro, origem explícita e segredos do orquestrador. Consulte
[docs/PRODUCTION_READINESS.md](docs/PRODUCTION_READINESS.md).

## Builds Android separados

O Android possui dois flavors para impedir que uma configuração de demo seja
publicada por engano:

```powershell
# Demo instalável, separada por arquitetura e ligada à API pública.
# Pode usar a chave de debug; HTTP local continua permitido para desenvolvimento.
flutter build apk --flavor demo --release --split-per-abi `
  --dart-define=GRANMAP_API_URL=https://granmap.168.119.244.43.sslip.io/api

# Produção; bloqueia HTTP e exige android/key.properties.
flutter build appbundle --flavor production --release `
  --dart-define=GRANMAP_API_URL=https://api.seudominio.edu.br
```

O backend também bloqueia `GRANMAP_COMMERCIAL_LAUNCH=true` quando planta,
calibração, SSO, ERP ou push ainda não estiverem configurados. Consulte
[docs/ENTRADAS_EXTERNAS.md](docs/ENTRADAS_EXTERNAS.md).

Para a publicação gerenciada, consulte
[deploy/cloudrun/README.md](deploy/cloudrun/README.md) para a API e
[deploy/cloudflare/README.md](deploy/cloudflare/README.md) para o painel e os
arquivos grandes.

Para o servidor ARM64 compartilhado do Web Lab/Coolify, use
[`compose.coolify.yaml`](compose.coolify.yaml) e o roteiro em
[`deploy/coolify/README.md`](deploy/coolify/README.md). Essa variante constrói
PostGIS para ARM64, aplica limites de CPU/RAM e não ocupa portas públicas do host.

## Publicação e download (v1.6.10)

A versão atual (`1.6.10+22`) está publicada com API FastAPI, PostgreSQL/PostGIS
e painel administrativo via `compose.coolify.yaml` em HTTPS:

- Portal e painel: `https://granmap.168.119.244.43.sslip.io`
- Página de instalação Android: `https://granmap.168.119.244.43.sslip.io/instalar`
- Download direto do APK: `https://granmap.168.119.244.43.sslip.io/baixar`
- Releases no GitHub: `https://github.com/deywysonc/GranMap/releases/latest`

Os APKs assinados de entrega ficam em `deliverables/` (ex.: `GranMap.apk`,
`GranMap-Android-arm64.apk`, `GranMap-32bits.apk` e `GranMap-apk.zip`).
Street View/Walk foi retirado da interface e do pacote de assets, conforme a
decisão do projeto. Os materiais originais de referência permanecem preservados.

## Limite conceitual do mapa

O software, a câmera e as fontes de sensores estão conectados, mas o mapa ainda
é conceitual. Portanto, posição, distância, ETA e alinhamento AR não são
alegados como precisos. Planta autorizada ou levantamento métrico, pontos
georreferenciados, placas QR instaladas, captura 360° e campanha magnética são
dados físicos que nenhum código consegue inventar. O roteiro está em
[docs/FIELD_SURVEY_PLAYBOOK.md](docs/FIELD_SURVEY_PLAYBOOK.md).
