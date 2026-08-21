# GranMap — demo vertical completa

**Status: concluída em 20/08/2026.**

## Objetivo

Entregar uma demonstração integrada da visão final do GranMap. A geometria da
Gran Tietê permanece conceitual até a planta ou o levantamento em campo, mas os
motores, contratos e fluxos devem ser reais e reaproveitáveis.

## Contrato de verdade

- nomes e catálogo institucional podem ser reais;
- geometria, escala, tempo e sinais simulados devem aparecer como demonstração;
- 2D, 3D, primeira pessoa e AR consomem o mesmo sistema X/Y/Z;
- nenhuma tela afirma precisão maior do que a confiança calculada;
- dados oficiais continuam com prioridade sobre contribuições comunitárias.

## Experiências do produto

- **GranMap Live:** navegação contínua, instrução atual, progresso, ETA da
  maquete, troca de piso, acessibilidade e recálculo;
- **Twin View:** Digital Twin 3D conceitual, pisos explodidos ou transparentes,
  rota 3D e destino destacado;
- **Walk View:** navegação em primeira pessoa dentro do mesmo Twin;
- **Gran Lens:** AR demonstrativo sobre câmera compatível, com modo simulado
  e preparação para âncoras reais;
- **Signal Halo:** representação visual da confiança e da incerteza;
- **GranMap Lab:** Nodes, Edges, coordenadas, sensores, confiança, logs e
  controles do simulador;
- **GranMap Admin:** operação acadêmica, conflitos, usuários, moderação e
  auditoria.

Os modos 2D, Twin, Walk e AR preservam uma única `NavigationSession`: iniciar,
pausar, acelerar ou trocar a visualização não reinicia a rota. A mesma posição
X/Y/Z atualiza instrução, piso, progresso, destino e confiança.

## Fontes de posição

O simulador determinístico, o Map Matching, o cálculo de confiança e as fontes
físicas já estão implementados. Sem o levantamento, as fontes reais operam em
modo de coleta/validação e não são chamadas de localização precisa:

1. simulador determinístico;
2. sensores reais do aparelho, fusão e PDR;
3. GPS real como leitura de apoio próxima às entradas;
4. câmera real e reancoragem por QR Code;
5. coleta e armazenamento versionado de fingerprints magnéticos.

O fluxo comum é: sensores → PDR → fusão → Map Matching → posição X/Y/Z com
confiança.

## Definição de concluído

Uma única rota deve poder ser iniciada pela busca ou pela próxima aula e
acompanhada sem perder estado no 2D, 3D, primeira pessoa e AR demonstrativo. A
posição deve avançar continuamente, mudar de piso, atualizar progresso e
instruções, respeitar acessibilidade e reagir a bloqueios. O fluxo acadêmico e
comunitário precisa fechar no Admin, com conflitos e auditoria. Um cenário de
dados determinístico deve permitir repetir toda a apresentação.

## Como demonstrar

1. Execute `scripts/start_demo.ps1` na raiz do repositório.
2. No app, pesquise um destino ou use a próxima aula e inicie a rota.
3. Alterne entre **2D**, **Twin**, **Walk** e **AR** durante o percurso.
4. Abra o **GranMap Lab** para mudar ruído, velocidade e inspecionar confiança,
   sensores, Nodes e Edges.
5. Entre como aluno para favoritos, histórico, grade e comunidade.
6. Entre no Admin como `admin@granmap.demo` para cadastros, conflitos, papéis,
   moderação e auditoria. A senha de todas as contas demo é `GranMap123!`.

## Validação registrada

- Flutter: análise estática limpa, 26 testes, build Web e APK debug;
- backend: 13 testes cobrindo segurança, mapa, operação, comunidade,
  notificações, papéis e conflitos;
- Admin: 3 testes do cliente seguro, compilação TypeScript e build Vite;
- cenário: 5 usuários, 3 cursos, 6 disciplinas, 3 turmas, 4 professores,
  27 salas, 6 horários e 2 contribuições comunitárias.

## Fora da alegação da demo

- precisão indoor real na Gran Tietê;
- distâncias oficiais ou tempo de caminhada validado;
- mapa magnético real sem campanha de coleta;
- alinhamento espacial validado de AR sem âncora física ou calibração;
- representação arquitetônica fiel antes da planta autorizada.
