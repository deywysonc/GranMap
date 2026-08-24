[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [string]$PublicOrigins,

    [string]$Region = "southamerica-east1",
    [string]$ServiceName = "granmap-api",
    [string]$Repository = "granmap",
    [string]$DatabaseSecret = "granmap-database-url",
    [string]$ImageTag = "latest"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    throw "Google Cloud CLI (gcloud) não está instalado."
}

$image = "$Region-docker.pkg.dev/$ProjectId/$Repository/${ServiceName}:$ImageTag"

gcloud config set project $ProjectId | Out-Null
gcloud services enable `
    run.googleapis.com `
    artifactregistry.googleapis.com `
    cloudbuild.googleapis.com `
    secretmanager.googleapis.com

$existingRepository = gcloud artifacts repositories describe $Repository `
    --location $Region `
    --format "value(name)" 2>$null

if (-not $existingRepository) {
    gcloud artifacts repositories create $Repository `
        --repository-format docker `
        --location $Region `
        --description "Imagens de produção do GranMap"
}

gcloud secrets describe $DatabaseSecret --format "value(name)" | Out-Null

$projectNumber = gcloud projects describe $ProjectId `
    --format "value(projectNumber)"
$runtimeServiceAccount = "$projectNumber-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding $DatabaseSecret `
    --member "serviceAccount:$runtimeServiceAccount" `
    --role "roles/secretmanager.secretAccessor" | Out-Null

gcloud builds submit . `
    --region $Region `
    --config deploy/cloudrun/cloudbuild.yaml `
    --substitutions "_IMAGE=$image"

gcloud run jobs deploy "$ServiceName-migrate" `
    --image $image `
    --region $Region `
    --command alembic `
    --args upgrade,head `
    --cpu 1 `
    --memory 512Mi `
    --max-retries 1 `
    --task-timeout 5m `
    --service-account $runtimeServiceAccount `
    --set-secrets "GRANMAP_DATABASE_URL=${DatabaseSecret}:latest"

gcloud run jobs execute "$ServiceName-migrate" `
    --region $Region `
    --wait

gcloud run jobs deploy "$ServiceName-retention" `
    --image $image `
    --region $Region `
    --command python `
    --args retention.py `
    --cpu 1 `
    --memory 512Mi `
    --max-retries 1 `
    --task-timeout 5m `
    --service-account $runtimeServiceAccount `
    --set-secrets "GRANMAP_DATABASE_URL=${DatabaseSecret}:latest"

gcloud run deploy $ServiceName `
    --image $image `
    --region $Region `
    --platform managed `
    --allow-unauthenticated `
    --port 8000 `
    --cpu 1 `
    --memory 512Mi `
    --concurrency 20 `
    --min 0 `
    --max 3 `
    --timeout 30 `
    --service-account $runtimeServiceAccount `
    --set-secrets "GRANMAP_DATABASE_URL=${DatabaseSecret}:latest" `
    --set-env-vars "GRANMAP_ENVIRONMENT=production,GRANMAP_PUBLIC_ORIGINS=$PublicOrigins,GRANMAP_COOKIE_SECURE=true,GRANMAP_TRUSTED_PROXY_HEADERS=true,GRANMAP_METRICS_ENABLED=false,GRANMAP_RUN_MIGRATIONS_ON_STARTUP=false,GRANMAP_ALLOW_REMOTE_DEMO_SEED=false,GRANMAP_DATABASE_POOL_SIZE=3,GRANMAP_DATABASE_MAX_OVERFLOW=2,GRANMAP_DATABASE_POOL_TIMEOUT_SECONDS=10,GRANMAP_DATABASE_POOL_RECYCLE_SECONDS=300,GRANMAP_MINIMUM_APP_BUILD=5,GRANMAP_LATEST_APP_BUILD=10,GRANMAP_COMMERCIAL_LAUNCH=false"

gcloud run services describe $ServiceName `
    --region $Region `
    --format "value(status.url)"
