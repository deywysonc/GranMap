$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot '.demo-pids.json'

if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Host 'Nenhum processo da demo foi registrado.'
    exit 0
}

$entries = @(Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json)

function Stop-GranMapProcessTree {
    param([int]$ProcessId)

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-GranMapProcessTree -ProcessId $child.ProcessId
    }

    Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
}

foreach ($entry in $entries) {
    $process = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        Stop-GranMapProcessTree -ProcessId $entry.pid
        Write-Host "Encerrado: $($entry.name) (PID $($entry.pid))"
    }
}

Remove-Item -LiteralPath $pidFile
