$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $repoRoot 'backend'
$demoDb = Join-Path $backendRoot 'granmap_demo.db'
$python = Join-Path $backendRoot '.venv\Scripts\python.exe'
$previousDb = $env:GRANMAP_DB_PATH

try {
    $env:GRANMAP_DB_PATH = $demoDb
    & $python (Join-Path $backendRoot 'reset_demo.py')
    if ($LASTEXITCODE -ne 0) { throw 'Reset da demo não concluído.' }
}
finally {
    if ($null -eq $previousDb) {
        Remove-Item Env:\GRANMAP_DB_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:GRANMAP_DB_PATH = $previousDb
    }
}
