$ErrorActionPreference = 'Stop'
$taskRepo = Split-Path -Parent $PSScriptRoot
& docker.exe compose --project-name granmap-pc --env-file (Join-Path $taskRepo '.secrets\pc.env') `
    -f (Join-Path $taskRepo 'compose.pc.yaml') --profile public stop
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível interromper a hospedagem.' }
Write-Host 'Hospedagem do GranMap interrompida. Banco, backups e arquivos preservados.'
