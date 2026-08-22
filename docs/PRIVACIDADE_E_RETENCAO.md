# Privacidade e retenção do GranMap

O GranMap coleta apenas os dados necessários para conta, personalização,
navegação e melhoria consentida do posicionamento. Localização e sensores
físicos permanecem desativados até a escolha explícita do usuário.

## Dados e finalidade

| Dado | Finalidade | Regra padrão |
|---|---|---|
| Perfil acadêmico | Grade e próxima aula | Enquanto a conta existir |
| Favoritos | Personalização | Até remoção ou exclusão da conta |
| Histórico de navegação | Recentes e retomada | 180 dias |
| Notificações lidas | Comunicação acadêmica | 90 dias |
| Eventos de autenticação | Segurança e investigação | 365 dias |
| Fingerprint magnético | Calibração indoor | Identidade removida após 180 dias |
| Contribuições e votos | Auditoria comunitária | Preservados de forma anônima após exclusão |

## Direitos do usuário

O aplicativo oferece exportação dos dados, alteração de senha, revogação de
sessões e exclusão da conta. Na exclusão, favoritos, histórico e notificações
são apagados. Registros comunitários necessários à integridade acadêmica ficam
anônimos.

## Operação

Execute `python retention.py` diariamente como job separado. Os prazos podem
ser alterados por variáveis `GRANMAP_RETENTION_*`, após aprovação da política
institucional. Backups devem respeitar a mesma política e ter expiração própria.
