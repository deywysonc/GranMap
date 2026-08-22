# GranMap no Google Cloud Run

Configuração de produção inicial da API:

- região `southamerica-east1` (São Paulo);
- 1 vCPU e 512 MiB por instância;
- concorrência 20;
- escala automática entre 0 e 3 instâncias;
- PostgreSQL externo no Neon;
- migrações executadas por um Cloud Run Job, antes da nova revisão;
- política de retenção empacotada no job `granmap-api-retention`;
- métricas públicas desativadas; logs e métricas ficam no Google Cloud.

## Pré-requisitos

1. Instale e autentique o Google Cloud CLI.
2. Crie ou selecione um projeto com faturamento habilitado.
3. Mantenha o projeto Neon na região AWS São Paulo e copie a URL com pooler.
4. Crie o segredo sem gravar a conexão no Git:

```powershell
$databaseUrl = Read-Host "Cole a URL pooled do Neon" -AsSecureString
$databaseUrlText = [System.Net.NetworkCredential]::new('', $databaseUrl).Password
$databaseUrlText | gcloud secrets create granmap-database-url --data-file=-
$databaseUrlText = $null
```

Se o segredo já existir, adicione uma nova versão usando
`gcloud secrets versions add granmap-database-url --data-file=-`.

## Publicação

Execute na raiz do repositório:

```powershell
.\deploy\cloudrun\deploy.ps1 `
  -ProjectId "SEU_PROJECT_ID" `
  -PublicOrigins "https://admin.seudominio.com.br"
```

O script valida o segredo, cria o repositório de imagens, constrói a imagem,
executa as migrações uma única vez e publica a API com limites de custo.

Antes de liberar usuários, crie um orçamento mensal com alertas em 50%, 90% e
100%. Alertas de orçamento avisam sobre gastos, mas não interrompem recursos;
os limites `--max 3` e `--concurrency 20` do serviço são a primeira proteção
contra escalabilidade acidental.

Não altere `GRANMAP_COMMERCIAL_LAUNCH` para `true` antes de aprovar o mapa,
concluir a calibração de campo e configurar as integrações institucionais.

Agende a execução diária do job `granmap-api-retention` pelo Cloud Scheduler
depois de habilitar o faturamento. Antes disso, ele pode ser executado
manualmente com:

```powershell
gcloud run jobs execute granmap-api-retention `
  --region southamerica-east1 `
  --wait
```
