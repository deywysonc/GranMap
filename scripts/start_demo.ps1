param(
    [switch]$NoReset,
    [switch]$Lan
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $repoRoot 'backend'
$adminRoot = Join-Path $repoRoot 'admin_web'
$appRoot = Join-Path $repoRoot 'app'
$distRoot = Join-Path $repoRoot 'dist'
$demoDb = Join-Path $backendRoot 'granmap_demo.db'
$pidFile = Join-Path $repoRoot '.demo-pids.json'
$python = Join-Path $backendRoot '.venv\Scripts\python.exe'
$npm = (Get-Command npm.cmd -ErrorAction Stop).Source
$flutter = (Get-Command flutter -ErrorAction Stop).Source

function Get-LanIPv4 {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne '0.0.0.0' } |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($null -eq $route) {
        throw 'Não foi possível detectar a rota de rede local.'
    }

    $address = Get-NetIPAddress `
        -InterfaceIndex $route.InterfaceIndex `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -ne '127.0.0.1'
        } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if ([string]::IsNullOrWhiteSpace($address)) {
        throw 'Não foi possível detectar o IPv4 da rede local.'
    }

    return $address
}

$bindHost = if ($Lan) { '0.0.0.0' } else { '127.0.0.1' }
$accessHost = if ($Lan) { Get-LanIPv4 } else { '127.0.0.1' }
$apiUrl = "http://${accessHost}:8100"
$adminUrl = "http://${accessHost}:5174"
$appUrl = "http://${accessHost}:8088"
$apkName = 'GranMap-demo-v12-completa.apk'
$apkPath = Join-Path $distRoot $apkName
$apkUrl = "http://${accessHost}:8090/$apkName"

if (-not (Test-Path -LiteralPath $python)) {
    throw 'Ambiente Python não encontrado. Execute a instalação descrita no README.'
}

if (-not $NoReset) {
    $previousDb = $env:GRANMAP_DB_PATH
    try {
        $env:GRANMAP_DB_PATH = $demoDb
        & $python (Join-Path $backendRoot 'reset_demo.py')
        if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preparar o cenário.' }
    }
    finally {
        if ($null -eq $previousDb) {
            Remove-Item Env:\GRANMAP_DB_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:GRANMAP_DB_PATH = $previousDb
        }
    }
}

function Test-LocalPort {
    param([int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $result = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(180)) { return $false }
        $client.EndConnect($result)
        return $true
    }
    catch { return $false }
    finally { $client.Dispose() }
}

function Wait-LocalPort {
    param([int]$Port, [int]$Seconds = 30)
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-LocalPort -Port $Port) { return }
        Start-Sleep -Milliseconds 250
    }
    throw "O serviço da porta $Port não iniciou a tempo."
}

$started = @()
if (Test-Path -LiteralPath $pidFile) {
    $registered = @(Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json)
    foreach ($entry in $registered) {
        if ($null -ne (Get-Process -Id $entry.pid -ErrorAction SilentlyContinue)) {
            $started += [pscustomobject]@{ name = $entry.name; pid = $entry.pid }
        }
    }
}

if (-not (Test-LocalPort -Port 8100)) {
    $backendEnvironment = @{ GRANMAP_DB_PATH = $demoDb }
    if ($Lan) {
        $backendEnvironment.GRANMAP_PUBLIC_ORIGINS = ConvertTo-Json `
            -InputObject @($adminUrl, $appUrl) `
            -Compress
    }

    $backendProcess = Start-Process `
        -FilePath $python `
        -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', $bindHost, '--port', '8100') `
        -WorkingDirectory $backendRoot `
        -WindowStyle Hidden `
        -Environment $backendEnvironment `
        -PassThru
    $started += [pscustomobject]@{ name = 'backend'; pid = $backendProcess.Id }
}

if (-not (Test-LocalPort -Port 5174)) {
    $adminProcess = Start-Process `
        -FilePath $npm `
        -ArgumentList @('run', 'dev', '--', '--host', $bindHost, '--port', '5174') `
        -WorkingDirectory $adminRoot `
        -WindowStyle Hidden `
        -Environment @{ VITE_GRANMAP_API_URL = $apiUrl } `
        -PassThru
    $started += [pscustomobject]@{ name = 'admin'; pid = $adminProcess.Id }
}

if (-not (Test-LocalPort -Port 8088)) {
    $appProcess = Start-Process `
        -FilePath $flutter `
        -ArgumentList @(
            'run', '-d', 'web-server',
            '--web-hostname', $bindHost,
            '--web-port', '8088',
            "--dart-define=GRANMAP_API_URL=$apiUrl"
        ) `
        -WorkingDirectory $appRoot `
        -WindowStyle Hidden `
        -PassThru
    $started += [pscustomobject]@{ name = 'app'; pid = $appProcess.Id }
}

if ($Lan -and (Test-Path -LiteralPath $apkPath) -and -not (Test-LocalPort -Port 8090)) {
    $downloadProcess = Start-Process `
        -FilePath $python `
        -ArgumentList @('-m', 'http.server', '8090', '--bind', $bindHost, '--directory', $distRoot) `
        -WorkingDirectory $repoRoot `
        -WindowStyle Hidden `
        -PassThru
    $started += [pscustomobject]@{ name = 'apk-download'; pid = $downloadProcess.Id }
}

$started | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding utf8

Wait-LocalPort -Port 8100
Wait-LocalPort -Port 5174
Wait-LocalPort -Port 8088 -Seconds 60
if ($Lan -and (Test-Path -LiteralPath $apkPath)) {
    Wait-LocalPort -Port 8090
}

Write-Host ''
Write-Host 'GranMap Demo pronta.' -ForegroundColor Green
Write-Host "App:   $appUrl"
Write-Host "Admin: $adminUrl"
Write-Host "API:   $apiUrl"
if ($Lan -and (Test-Path -LiteralPath $apkPath)) {
    Write-Host "APK:   $apkUrl"
}
Write-Host 'Aluno: aluno@granmap.demo / GranMap123!'
Write-Host 'Admin: admin@granmap.demo / GranMap123!'

Start-Process $appUrl
