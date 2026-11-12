# Roadmap

## Concluído sem planta

- contrato conceitual v6 e catálogo real de salas;
- rotas relativas entre pisos e avisos contra métricas falsas;
- conta, perfil acadêmico, favoritos e histórico;
- comunidade autenticada, consenso, reputação e fila offline;
- governança por papéis, moderação e auditoria;
- testes de integridade do mapa, alinhamento com backend e regras comunitárias.
- autenticação Argon2id, sessão móvel segura e cookie HttpOnly/CSRF no Admin;
- mapa versionado, bloqueios, recálculo e âncoras QR;
- câmera, sensores físicos, fusão, PDR, GPS de apoio e coleta magnética;
- notificações da grade e aplicação auditável de propostas confirmadas;
- PostgreSQL/PostGIS, Alembic, containers, métricas e CI.

## Demo vertical completa — concluída

1. GranMap Live com posição contínua, progresso, confiança e acessibilidade.
2. GranMap Lab com sensores simulados/físicos, coleta magnética, logs e grafo.
3. Digital Twin 3D conceitual usando o mesmo mapa X/Y/Z.
4. Walk View em primeira pessoa e troca automática de piso.
5. Gran Lens com câmera real opcional, AR demonstrativo e âncoras QR.
6. PDR, fusão, Map Matching e confiança com fonte real ou determinística.
7. Admin completo, papéis e conflitos acadêmicos.
8. Dados, reset e inicialização em um clique para a apresentação.

Essas oito frentes estão implementadas e validadas. As interfaces e os
algoritmos e integrações físicas são funcionais. Geometria, métricas e precisão
continuam identificadas como provisórias enquanto não houver calibração real.

## Validação na faculdade

1. Conferir nomes, portas, lados do corredor e acessibilidade presencialmente.
2. Fotografar ou desenhar pontos de decisão, sem registrar pessoas.
3. Validar rotas com estudantes, funcionários e usuários com mobilidade
   reduzida.
4. Corrigir o grafo conceitual mantendo IDs estáveis.

## Quando a planta chegar

1. Importar planta autorizada e registrar escala por piso.
2. Ancorar POIs e nós do grafo em coordenadas métricas.
3. Medir trechos e validar estimativas de tempo.
4. Modelar rotas acessíveis e bloqueios temporários.
5. Calibrar as fontes reais já integradas e medir precisão por aparelho.
6. Instalar e cadastrar placas QR em entradas e pontos de decisão.

## Dependências externas antes da operação comercial

- domínio/TLS, segredos, backup restaurável, alertas e retenção;
- aprovação institucional da planta e do tratamento de dados;
- integração SSO/ERP/grade oficial e credenciais de push FCM/APNs;
- campanha de acessibilidade, carga, segurança e testes com usuários;
- levantamento, QR, fingerprints e conteúdo 360 descritos no playbook de campo.
