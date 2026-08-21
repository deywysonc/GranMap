# Produto GranMap

## Propósito

Reduzir a incerteza de quem precisa encontrar uma sala, serviço ou aula dentro
da faculdade. O GranMap reúne orientação, contexto acadêmico e conhecimento
coletivo sem substituir a fonte institucional.

## Princípios

1. **Verdade antes da aparência.** Geometria conceitual nunca é apresentada
   como planta, metro ou tempo real.
2. **Oficial tem prioridade.** Ensalamento e cadastro institucional só podem
   ser alterados por coordenação ou administração.
3. **Comunidade é evidência.** Alunos informam mudanças e votam; consenso ajuda
   a triagem, mas não reescreve silenciosamente a base oficial.
4. **Funciona em conexão ruim.** Mapa e dados recentes ficam no aparelho;
   contribuições aguardam sincronização.
5. **Privacidade por padrão.** O app guarda apenas os dados necessários para
   conta, personalização, histórico e reputação.

## Papéis

- `student` e `professor`: usam o app, criam propostas e votam;
- `moderator`: revisa propostas e consulta auditoria;
- `coordination` e `admin`: também mantêm dados oficiais.

Uma proposta começa como `unverified`, passa a `voting` com votos e, a partir
de cinco votos, pode tornar-se `confirmed` (75% ou mais de concordância) ou
`contested` (35% ou menos). A moderação pode confirmar, contestar ou rejeitar.
O autor recebe 1 ponto ao contribuir e mais 2 na primeira confirmação.

## Limite atual

O produto ainda não possui planta métrica validada. O mapa 2D atual é uma
topologia corrigida: diferencia o que foi filmado, o que foi confirmado pelo
autor, o que foi apenas informado e o que ainda não foi localizado. A demo já apresenta
posição contínua, confiança, Digital Twin 3D, Walk View, câmera real opcional,
QR, sensores físicos, PDR e coleta magnética. Esses componentes estão
funcionais, mas não podem prometer precisão na Gran Tietê antes de existirem
levantamento físico, placas instaladas, fingerprints coletados e validação com
rotas reais. O modo simulado permanece como fallback reproduzível.
