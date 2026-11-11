# GranMap 1.6.1 — confiabilidade e acabamento

Atualização de 14/10/2026, build Android 13, API local 0.12.1.

## Corrigido

- Comunidade não mistura cache, votos e propostas entre contas.
- Uma transação local mantém a fila de envio e a representação visível juntas.
- Respostas e gravações tardias não apagam operações adicionadas depois.
- Repetições de votos preservam a intenção mais recente; cada alteração tem
  sua versão persistida. A API 0.12.1 ignora revisões antigas e repetidas.
- Pendências sincronizam com o app aberto, mesmo fora da tela Comunidade;
  pausa ao ir para segundo plano e tenta novamente ao retornar.
- Falhas definitivas têm uma ação de reenvio. Mensagens não confundem uma
  alteração offline com confirmação do servidor.
- Notificações usam cache primeiro, terminam a espera em falhas e oferecem
  retry. A leitura só é indicada após confirmação do servidor.
- Troca de conta, logout e callbacks de telas antigas não expõem dados de outra
  conta nem enviam ações em nome dela.
- Cadastro usa os mesmos limites da API: senha de 10–128 caracteres, nome de
  2–100, e-mail de até 160, turma de até 60, semestre de 1–20. A edição de perfil
  agora também aceita o intervalo completo de semestres.
- Duplo toque não empilha logins nem duplica envios ativos da comunidade.

## Evidências

201 testes Flutter, 29 testes da API SQLite e 3 do Admin aprovados.
Análise Flutter sem problemas. Builds web, Admin e três arquiteturas Android
concluídos. Jornada HTTP local aprovada, sem recriar o banco da demo.

APK ARM64: `deliverables/GranMap-Demo-v1.6.1-arm64-v8a.apk`, 27.833.692 bytes.
SHA-256: `9B1F9060C9766D4DF06DDD358E1D73E1E1A9F3115EE9A761FBFB2349B8DCDDE7`.
Assinatura v2 validada e certificado de demo preservado; Android mínimo 7.0.
Os APKs ARM 32 bits e x86_64 ficam na mesma pasta. Não houve retirada de
funcionalidades para reduzir o tamanho.

## Publicação e limites reais

Os artefatos estão locais. Nenhum push, deploy ou alteração do download público
foi feito. O APK aponta para a API HTTPS pública existente. Para ativar a proteção
de revisão dos votos também nesse endereço, publicar a API 0.12.1 e aplicar
`alembic upgrade head` no PostgreSQL. O Alembic não está instalado no ambiente
virtual local; a migração foi compilada, mas não executada contra PostgreSQL.
SQLite aplica a coluna nova automaticamente na inicialização.

Não havia celular ou emulador conectado. Instalação, sensores, câmera, permissões
e posicionamento na faculdade ainda exigem validação física. A planta do térreo
e a escala das distâncias permanecem aproximadas. SMTP, SSO/ERP, push e requisitos
de lançamento comercial dependem da configuração institucional existente.

A barreira de gravação só é liberada quando a operação nativa termina: se o
armazenamento parar de responder permanentemente, o app informa erro em vez de
permitir uma sobrescrita tardia. O FIFO cobre instâncias do mesmo processo;
ordenação entre aparelhos com relógios divergentes não foi validada.

A tentativa visual deste dia recebeu a versão anterior no navegador e depois
teve a consulta da versão bloqueada. Não se declara aprovação visual da 1.6.1
a partir dessa sessão; os controles e estados foram cobertos pelos testes de
interface e a prévia nova pode ser aberta em `http://127.0.0.1:8089/`.
