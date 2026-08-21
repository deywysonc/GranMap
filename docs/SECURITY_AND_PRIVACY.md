# Segurança e privacidade

## Dados tratados

Conta acadêmica, perfil, grade, favoritos, histórico, contribuições,
notificações e telemetria de posicionamento estritamente necessária. A câmera
AR é processada no aparelho; o GranMap não envia frames ao backend. O QR contém
um identificador de âncora, não dados pessoais.

Fingerprints magnéticos guardam X/Y/Z, vetor magnético, qualidade e modelo do
aparelho. A política institucional deve definir retenção e acesso; a coleta
fica restrita a papéis de operação.

## Controles já implementados

- Argon2id e migração transparente de PBKDF2;
- token aleatório armazenado como hash, expiração, revogação e último uso;
- credencial móvel no armazenamento seguro e cookie web HttpOnly/CSRF;
- papéis, validação de conflitos e trilha de auditoria;
- rate limit de login, headers de segurança e métricas sem conteúdo pessoal;
- confiança explícita para não apresentar posição incerta como exata.

## Controles organizacionais obrigatórios

- base legal/consentimento e aviso de privacidade aprovado;
- canal para acesso, correção, exportação e exclusão conforme a política;
- revisão periódica de papéis, incident response e rotação de segredos;
- backup criptografado, restauração testada e retenção mínima;
- avaliação de fornecedores de SSO, push, e-mail, nuvem e analytics;
- não usar imagens 360° sem autorização e tratamento de rostos/documentos.
