# GranMap — prontidão para produção

## O que a base já resolve

| Frente | Implementação atual |
|---|---|
| App | Flutter, 2D/3D/Walk/AR, A*, acessibilidade, PDR, QR, GPS de apoio e offline |
| Segurança | Argon2id, migração de hash, sessão revogável, recuperação de senha, Keychain/Keystore, HttpOnly + CSRF |
| Dados | SQLite de desenvolvimento; PostgreSQL/PostGIS + Alembic em produção |
| Operação | mapa versionado, ETag, âncoras, bloqueios e recálculo automático |
| Acadêmico | grade, próxima aula, conflitos, mudança oficial e notificação |
| Comunidade | proposta, voto único, confiança, reputação, moderação e auditoria |
| Confiabilidade | idempotência, fila offline com backoff, ETag, version gate, diagnóstico e request ID |
| Privacidade | consentimentos persistentes, exportação/exclusão da conta e retenção automatizada |
| Entrega | Docker, Nginx, healthcheck, Prometheus, APKs por arquitetura e CI multi-stack |

## Configuração comercial mínima

1. Publique Admin e API atrás de TLS; configure origem exata e cookie seguro.
2. Guarde senha do PostgreSQL e demais credenciais em secret manager.
3. Execute `alembic upgrade head` como job único antes dos workers.
4. Faça backup criptografado e teste restauração em ambiente separado.
5. Colete `/metrics`, logs da aplicação e alertas de disponibilidade/latência.
6. Remova HTTP liberado do Android/iOS no flavor de release.
7. Agende `python retention.py` e valide a política descrita em `PRIVACIDADE_E_RETENCAO.md`.
8. Realize pentest, teste de carga, contraste/leitor de tela e piloto assistido.

O `compose.yaml` é adequado para desenvolvimento e homologação. Em produção,
use serviço PostgreSQL gerenciado ou volume com backup, pelo menos duas
instâncias da API, proxy HTTPS e observabilidade externa.

## Integrações que exigem terceiros

- SSO/identidade e importação automática da grade dependem do IdP/ERP da faculdade.
- Push fora do aplicativo depende de projeto FCM/APNs e consentimento do usuário.
- Publicação nas lojas depende de contas, certificados e políticas da instituição.
- Alertas, e-mail de recuperação e suporte dependem dos provedores escolhidos.
- A versão de loja exige uma chave definitiva da instituição; a assinatura de debug é apenas para a demo.

O feed de notificações dentro do app já funciona sem esses provedores.

## Critério de go-live

O lançamento não deve alegar distância, ETA ou precisão indoor até que a versão
publicada do mapa tenha `geometryStatus`, `distanceStatus` e escala validados.
O piloto deve medir erro P50/P95, taxa de conclusão de rota, reancoragens,
consumo de bateria e desempenho por modelo de aparelho.

O checklist executável e os artefatos atuais estão em `RELEASE_CHECKLIST.md`.
