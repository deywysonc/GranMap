param([switch]$Public)
$ErrorActionPreference = 'Stop'
$taskRepo = Split-Path -Parent $PSScriptRoot
$taskEnvironment = Join-Path $taskRepo '.secrets\pc.env'
if (-not (Test-Path -LiteralPath $taskEnvironment)) {
    throw 'Configure primeiro .secrets/pc.env conforme deploy/pc/README.md.'
}
foreach ($taskArtifact in @('dist\pc-web\index.html', 'dist\pc-admin\index.html', '.secrets\pc-bootstrap\source.db')) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskRepo $taskArtifact))) {
        throw "Artefato ausente: $taskArtifact. Consulte deploy/pc/README.md."
    }
}
$taskArguments = @('compose', '--project-name', 'granmap-pc', '--env-file', $taskEnvironment,
    '-f', (Join-Path $taskRepo 'compose.pc.yaml'))
& docker.exe @taskArguments build backend gateway
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível construir os serviços do GranMap.' }
if ($Public) { $taskArguments += @('--profile', 'public') }
& docker.exe @taskArguments up -d
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível iniciar a hospedagem.' }
Write-Host 'GranMap no PC: http://127.0.0.1:8787/'
Write-Host 'Banco e backups foram preservados. Nenhum reset foi executado.'
if ($Public) {
    Write-Host 'O túnel é temporário; confira o endereço HTTPS nos logs abaixo.'
    & docker.exe @taskArguments logs --tail 30 tunnel
}
