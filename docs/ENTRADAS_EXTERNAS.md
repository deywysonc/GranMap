# Entradas externas para o lançamento comercial

O software está preparado para receber os itens abaixo, mas eles precisam ser
fornecidos ou executados pela instituição. O GranMap não deve gerar dados
físicos fictícios para preencher essas lacunas.

| Entrada | Responsável | Evidência para concluir |
|---|---|---|
| Planta autorizada e escala por piso | Instituição/engenharia | arquivo aprovado e pontos de controle medidos |
| Rotas acessíveis | Instituição + usuários | larguras, inclinações, obstáculos e teste presencial |
| QR de reancoragem | Operação | placas instaladas e códigos vinculados a Nodes |
| Fingerprints magnéticos | Equipe de campo | amostras em vários aparelhos e relatório P50/P95 |
| Conteúdo 360° | Comunicação/privacidade | panoramas autorizados, sem rostos/documentos |
| SSO e ERP | TI institucional | issuer/client e contrato da API acadêmica |
| Push | TI do produto | projeto FCM/APNs e credenciais protegidas |
| E-mail transacional | TI do produto | SMTP/API validado para recuperação de senha |
| Loja | Instituição | contas, chave Android definitiva e certificados Apple |
| Produção | DevOps | domínio, TLS, PostgreSQL, backup testado e alertas |

O endpoint `GET /integrations/status` apresenta somente o estado dessas
dependências, sem expor URLs privadas ou segredos. Em produção, defina
`GRANMAP_COMMERCIAL_LAUNCH=true` apenas após todos os itens obrigatórios estarem
configurados; o backend bloqueará a inicialização se a preparação estiver
incompleta.
