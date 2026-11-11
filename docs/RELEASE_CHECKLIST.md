# GranMap — checklist de entrega

## Versão validada

- aplicativo: `1.6.3+15`;
- backend publicado no PC: `0.12.1`, ambiente de produção PostgreSQL/PostGIS;
- Admin: `0.5.0`;
- API do APK: URL HTTPS do PC registrada em `.secrets/pc-access.txt`, rota `/api`;
- APK recomendado: `deliverables/GranMap-Demo-v1.6.3-pc-arm64-v8a.apk`;
- tamanho: 27.834.576 bytes (26,5 MiB; 27,8 MB decimais);
- SHA-256: `B905042EE65E2D14E826D2885AF2D24AA892EFEECE24121D9F48708C2BD29736`;
- download publicado: `/instalar` e `/downloads/GranMap-Android-arm64.apk`.

O aplicativo web, API, Admin e APK foram publicados no PC em projeto Docker
isolado `granmap-pc`. A migração PostgreSQL `20261014_0003` está aplicada.
O endereço anterior do Coolify/GitHub não foi modificado e não deve ser
confundido com esta publicação. Não houve push ao GitHub.

O APK é assinado corretamente com APK Signature Scheme v2 e usa a chave de
debug apenas para instalação da demo. A loja exige a chave definitiva da
instituição e o flavor `production`.

## Atualização de 15/10/2026 — 1.6.3

224 testes Flutter, 49 de backend/bootstrap, 3 do Admin e 4 de snapshot passaram;
análise sem problemas, web e três arquiteturas Android compiladas. Área ampla
superior, frente da quadra e maquete conferidas. Download público completo,
assinatura, URL/planta incluídas no APK e retomada HTTP 206 aprovados.
Revisão: `pc-floorplan-v12-20261015-circulation`, 61 zonas/104 nós/117 ligações.
O túnel havia mudado de endereço após reiniciar o ambiente entre as sessões;
origem e APK agora usam o endereço atual registrado em `.secrets/pc-access.txt`.
Backups anteriores preservados e novo backup da versão com catálogo conferido.
Detalhes em [RELEASE_NOTES_V1_6_3.md](RELEASE_NOTES_V1_6_3.md).

## Verificações da versão-base 1.6.2 em 14/10/2026

- `flutter analyze`: aprovado;
- `flutter test`: 215 testes aprovados;
- backend e bootstrap: 49 testes aprovados;
- Admin: 3 testes aprovados;
- snapshots: 4 testes aprovados;
- build de produção do Admin: aprovado;
- build web de release: aprovado;
- build Android separado em ARM64, ARM 32 bits e x86_64: aprovado;
- assinatura, pacote, SDK e presença do mapa v12: aprovados;
- Street View/Walk ausente da interface e dos assets empacotados;
- jornada HTTPS pública: login de aluno/administrador, grade, comunidade,
  conflitos, mapa com 44 locais e versão anunciada 14 aprovados;
- download público completo com SHA-256 idêntico e retomada HTTP 206 aprovada;
- arquivos privados, métricas, documentação da API e listagem de downloads bloqueados;
- credencial privilegiada antiga da demo rejeitada com 401;
- backup PostgreSQL restaurado em cópia isolada, com contagens e migração conferidas;
- ordenação de votos atrasados e concorrentes validada no PostgreSQL restaurado;
- a cópia de teste foi removida; banco ativo e backups preservados.
- regressões de comunidade: isolamento de conta, concorrência, persistência
  tardia, fila atômica, último voto, sincronização no foreground e duplo toque;
- regressões de notificações: cache/rede travados, retry, troca de conta,
  confirmação de leitura e callback de sessão antiga;
- cadastro alinhado ao servidor e edição de perfil compatível até semestre 20.

A revisão visual da publicação 1.6.2 foi concluída no endereço público:
instalação, dois grupos de Química, lanchonete/rampa e Agronomia/rampa superior.
O 3D também foi conferido em 390 × 844. Evidências PNG em `deliverables/GranMap-PC-*`.
A prévia local `http://127.0.0.1:8089/` agora usa o mesmo gateway e API publicados.

Não havia aparelho Android conectado nem emulador configurado. A instalação,
as permissões e a calibração dos sensores físicos ainda precisam de teste no
celular. Os testes de interface usam uma tela de 360 × 800, incluindo rota
entre pisos no mapa completo, controles, QR simulado e confirmação manual.

## Demonstração na rede local

Para a hospedagem publicada neste PC, use `scripts/start_pc_host.ps1 -Public`
e `scripts/stop_pc_host.ps1`, conforme `deploy/pc/README.md`. O comando abaixo
é somente para o cenário de desenvolvimento, não para a instalação pública:

Execute:

```powershell
cd C:\GranMap
.\scripts\start_demo.ps1 -Lan -NoReset
```

O script agora prefere a rede privada real a adaptadores VPN. O telefone e o
computador precisam estar na mesma rede, e o computador precisa permanecer
ligado. Para validar todos os serviços e o download:

```powershell
.\scripts\verify_demo.ps1 `
  -ApiBase http://192.168.1.11:8100 `
  -AppUrl http://192.168.1.11:8088 `
  -AdminUrl http://192.168.1.11:5174 `
  -ApkUrl http://192.168.1.11:8090/GranMap-demo-v1.6.1-arm64.apk
```

## Antes do lançamento público

- configurar um endereço fixo/túnel nomeado antes de distribuir como serviço permanente;
- validar disponibilidade, energia, rede e restauração em outra máquina;
- cadastrar domínio, TLS, PostgreSQL gerenciado, backup e alertas;
- configurar SMTP, SSO/ERP e push, ou manter as chaves desativadas;
- criar e guardar a chave Android definitiva em cofre seguro;
- executar teste em aparelhos físicos e teste de carga;
- aprovar planta, escala, acessibilidade e campanha de posicionamento em campo;
- preencher os formulários de privacidade e conteúdo da loja.

Esses itens dependem de credenciais, medições ou decisões institucionais. O
backend bloqueia `GRANMAP_COMMERCIAL_LAUNCH=true` enquanto a configuração
obrigatória estiver incompleta.
