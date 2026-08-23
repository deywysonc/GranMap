param(
    [string]$ApiBase = 'http://127.0.0.1:8100',
    [string]$AppUrl = 'http://127.0.0.1:8088',
    [string]$AdminUrl = 'http://127.0.0.1:5174',
    [string]$ApkUrl = 'http://127.0.0.1:8090/GranMap-demo-v17-arm64.apk'
)

$ErrorActionPreference = 'Stop'

function Assert-HttpOk {
    param([string]$Url)
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -Method Get
    if ($response.StatusCode -ne 200) {
        throw "Falha HTTP em ${Url}: $($response.StatusCode)"
    }
    return $response.RawContentLength
}

function Login-Demo {
    param([string]$Email)
    $body = @{ email = $Email; password = 'GranMap123!' } | ConvertTo-Json
    return Invoke-RestMethod `
        -Uri "$ApiBase/auth/login" `
        -Method Post `
        -ContentType 'application/json' `
        -Body $body
}

$appBytes = Assert-HttpOk -Url $AppUrl
$adminBytes = Assert-HttpOk -Url $AdminUrl
$apkBytes = Assert-HttpOk -Url $ApkUrl
$health = Invoke-RestMethod -Uri "$ApiBase/health"
$map = Invoke-RestMethod -Uri "$ApiBase/maps/current"
$integrations = Invoke-RestMethod -Uri "$ApiBase/integrations/status"

$student = Login-Demo -Email 'aluno@granmap.demo'
$studentHeaders = @{ Authorization = "Bearer $($student.token)" }
$schedule = @(Invoke-RestMethod -Uri "$ApiBase/me/schedule" -Headers $studentHeaders)
$notifications = @(Invoke-RestMethod -Uri "$ApiBase/me/notifications" -Headers $studentHeaders)
$proposals = @(Invoke-RestMethod -Uri "$ApiBase/proposals" -Headers $studentHeaders)

$admin = Login-Demo -Email 'admin@granmap.demo'
$adminHeaders = @{ Authorization = "Bearer $($admin.token)" }
$conflicts = @(Invoke-RestMethod -Uri "$ApiBase/schedule-conflicts" -Headers $adminHeaders)
$versions = @(Invoke-RestMethod -Uri "$ApiBase/maps/versions" -Headers $adminHeaders)
$audits = @(Invoke-RestMethod -Uri "$ApiBase/audit" -Headers $adminHeaders)

$nodeCount = @($map.map_data.nodes).Count
$poiCount = @($map.map_data.pois).Count
if ($nodeCount -eq 0 -or $poiCount -eq 0) { throw 'O mapa publicado está vazio.' }
if ($schedule.Count -eq 0) { throw 'A conta de aluno não possui grade para a demo.' }
if ($versions.Count -eq 0) { throw 'Nenhuma versão de mapa foi encontrada.' }

[pscustomobject]@{
    Status = 'APROVADA'
    Api = "$($health.status) v$($health.version)"
    AppBytes = $appBytes
    AdminBytes = $adminBytes
    ApkBytes = $apkBytes
    MapNodes = $nodeCount
    MapPois = $poiCount
    StudentClasses = $schedule.Count
    Notifications = $notifications.Count
    Proposals = $proposals.Count
    ScheduleConflicts = $conflicts.Count
    MapVersions = $versions.Count
    AuditEvents = $audits.Count
    CommercialReady = $integrations.ready
} | Format-List
