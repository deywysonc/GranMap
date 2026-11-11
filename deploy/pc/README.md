# GranMap hospedado neste PC

Esta instalação é separada da demo de desenvolvimento e dos outros projetos
Docker do computador. Não usa Coolify e não abre portas no roteador.

## Estrutura e dados

- Projeto Docker: `granmap-pc`, definido em `compose.pc.yaml`.
- PostgreSQL/PostGIS persistente: volume `granmap-pc_pc_database`.
- API em modo produção, sem seed remoto, código de recuperação de desenvolvimento,
  documentação pública ou métricas abertas.
- Aplicativo: build Flutter release em `dist/pc-web`, API relativa `/api`.
- Painel: build React em `dist/pc-admin`, base `/admin/` e API `/api`.
- Downloads: somente APK ARM64 aprovado e checksum em `dist/pc-downloads`.
- Senhas: `.secrets/pc.env`, ignorado pelo Git. Não compartilhe esse arquivo.
- Backup inicial SQLite: `.secrets/pc-bootstrap/source.db`, montado somente para
  leitura. O banco original `backend/granmap_demo.db` não é modificado.
  Preserve esse snapshot junto com os backups de recuperação.
- Backups PostgreSQL diários: `.secrets/pc-backups`. Não há exclusão automática.

O bootstrap importa a cópia SQLite uma única vez, em transação, antes da API.
Não importa sessões, códigos de recuperação ou buckets de rate limit. Senhas
privilegiadas documentadas da demo são trocadas somente na cópia PostgreSQL.
Uma conta administrativa própria é configurada por ambiente; senha nunca deve
aparecer em argumentos de comandos, logs, repositório ou resposta pública.

## Iniciar e interromper

Com Docker Desktop aberto e os artefatos preparados:

```powershell
cd C:\GranMap
.\scripts\start_pc_host.ps1 -Public
```

Para interromper somente o GranMap, preservando dados:

```powershell
.\scripts\stop_pc_host.ps1
```

Nunca use `down -v`, `docker volume prune`, reset da demo ou exclusão do volume
para atualizar essa instalação. A demo de desenvolvimento continua independente.

Os endereços locais são `http://127.0.0.1:8787/` e a prévia existente em
`http://127.0.0.1:8089/`. Somente essas portas ficam vinculadas ao loopback;
banco e API não publicam portas no Windows. HTTPS externo
é fornecido pelo túnel. O login web com cookies seguros deve ser usado em HTTPS.

## Link público temporário

O serviço `tunnel` usa a imagem oficial de `cloudflared`. Veja o endereço em:

```powershell
docker compose --env-file .secrets/pc.env -f compose.pc.yaml --profile public logs --tail 30 tunnel
```

Quick Tunnels não exigem conta ou domínio, mas são para testes: sem garantia de
disponibilidade, até 200 requisições simultâneas, sem SSE e endereço novo a cada
reinício do túnel. Fonte: [documentação oficial](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

O PC, Docker Desktop e conexão à internet precisam continuar funcionando.
Suspender ou desligar o PC interrompe o acesso. Nenhuma configuração de energia,
inicialização automática ou firewall do Windows é alterada pelo projeto.

O aplicativo web usa a mesma origem e acompanha o endereço corrente. O APK
precisa ser compilado com a URL HTTPS exata do servidor; se um Quick Tunnel
mudar de nome, o APK anterior continua apontando para o endereço antigo.
Não anuncie esse link temporário como lançamento oficial permanente.

Para um endereço fixo, configure um túnel nomeado e domínio autorizado pelo
proprietário. Essa configuração não está presumida nem cria custos automaticamente.

## Atualizar artefatos

1. Faça backup do banco em uso e verifique sua integridade.
2. Compile Flutter release com `--dart-define=GRANMAP_API_URL=/api` para web.
3. Compile o Admin com `VITE_GRANMAP_API_URL=/api` e `--base=/admin/`.
4. Publique somente os arquivos web, `index.html` e `assets` do Admin; não copie
   seus downloads legados, documentos ou a raiz do repositório.
5. Compile APK demo ARM64 com a URL pública `/api`, valide assinatura, pacote,
   versão e SHA-256 antes de substituir o único APK disponibilizado.
6. Atualize `GRANMAP_PC_PUBLIC_ORIGIN` e a versão anunciada, se necessário.
7. Reinicie apenas os serviços modificados. Não reinicie o túnel à toa.
8. Teste login, papéis, mapa, grade, comunidade, download completo e resposta Range.

As migrações PostgreSQL são executadas antes do bootstrap/API. O bootstrap é
idempotente e não sobrescreve uma instalação já inicializada. A publicação de
uma revisão do mapa deve usar o fluxo autenticado de versões do Admin/API.

Os backups diários são formato custom do `pg_dump`, conferidos com `pg_restore
--list`. Para recuperação, restaure em banco separado e valide antes de trocar
o banco ativo; não restaure diretamente sobre produção sem confirmação e backup.
