# Arquitetura

## Componentes

- `app/`: Flutter, experiência do aluno e mapa local-first;
- `backend/`: FastAPI; SQLite no desenvolvimento e PostgreSQL/PostGIS em produção;
- `admin_web/`: React/Vite, operação institucional protegida por papéis;
- `app/assets/maps/gran_tiete_user_corrected_v10.json`: grafo canônico corrigido pelos vídeos e pelas marcações do autor;
- `backend/room_catalog.py`: contrato dos ambientes acadêmicos no servidor.

## Fluxos

### Navegação

O JSON traz zonas visuais, POIs, nós e arestas. O app calcula o menor caminho
por custo relativo. Como `scale_status` não está validado, `distanceMeters` e
tempo físico permanecem ausentes e a interface informa que o traçado é
conceitual.

### Dados pessoais e autenticação

Novas senhas usam Argon2id; hashes PBKDF2 antigos são migrados no login.
Sessões usam tokens aleatórios e somente o hash é persistido. O app móvel
guarda a credencial em Keychain/Keystore; o Admin usa cookie HttpOnly,
SameSite, CSRF e revogação. Favoritos, histórico, horários, notificações e mapa
possuem cache local SQLite no aparelho.

### Comunidade

O backend deriva autor e eleitor da sessão. O índice único de voto por
`proposal_id + voter_user_id` impede duplicação, mas permite que o usuário
corrija sua escolha. Mudanças de status e ações oficiais entram em
`audit_log`. O app mantém uma fila ordenada de operações offline e a drena na
próxima carga com conectividade.

### Governança

Leituras acadêmicas são públicas. Escritas em cursos, professores, salas e
horários exigem `coordination` ou `admin`. Moderação e auditoria aceitam
`moderator`, `coordination` ou `admin`. Uma contribuição confirmada só altera
o ensalamento após seleção explícita da aula por coordenação/admin, nova
checagem de conflitos, auditoria e notificação da turma.

## Evolução do banco

`db.init_db()` mantém a demo SQLite e atualiza bancos antigos. Produção executa
Alembic antes dos workers e usa o schema PostGIS. `PostgresCompatConnection`
é uma ponte para endpoints legados; autenticação, mapa e notificações já estão
em routers separados.

## Posicionamento

`DeviceSensorService` combina acelerômetro, giroscópio, magnetômetro e
barômetro quando disponíveis. A direção corrige a integração giroscópica com
o campo magnético; o PDR transforma passos em deslocamento e o `MapMatcher`
projeta a estimativa no grafo. QR redefine X/Y/Z e confiança. GPS apenas apoia
as entradas até existirem pontos georreferenciados. O simulador usa o mesmo
contrato e permanece como fallback.

## Operação do mapa

O mapa publicado possui versão, checksum e ETag. O Admin cria rascunhos
validados, publica versões e administra bloqueios e âncoras. O app consulta
bloqueios durante a navegação e executa A* novamente a partir do Node ativo.
Fingerprints magnéticos sempre apontam para a versão usada na coleta.

## Implantação

O `compose.yaml` contém PostGIS, API migrada e Admin/Nginx. A CI valida os dois
bancos, Flutter e React. Prometheus coleta `/metrics`. TLS, segredos, backup e
alertas são responsabilidades do ambiente de produção.
