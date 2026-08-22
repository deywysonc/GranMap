[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'app\assets\maps\gran_tiete_user_corrected_v10.json'
$targetPath = Join-Path $root 'app\assets\maps\gran_tiete_upper_floorplan_v11.json'
$map = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8 | ConvertFrom-Json

$map.building.version = '0.11-upper-floorplan-v11'
$map.metadata.geometryStatus = 'floorplan_relative'
$map.metadata.distanceStatus = 'provisional'
$map.metadata.coordinateSystem = 'navigation_conceptual_xyz_with_floorplan_display_xy'
$map.metadata.distanceUnit = 'conceptual_unit'
$map.metadata.surveyStatus = 'upper_floorplan_pdf_plus_four_walkthroughs_and_author_corrections_v11'
$map.metadata.importantNote = 'O piso superior foi redesenhado a partir da planta PAV.SUPERIOR-Gran Tietê-Layout1.pdf. A rampa para o térreo foi acrescentada no canto inferior esquerdo conforme correção do autor. A sequência física dos ambientes está baseada na planta; a associação dos nomes acadêmicos às salas ainda precisa de conferência presencial.'
$map.metadata.mapMode = 'upper_floorplan_relative_with_navigation_topology'
$map.metadata | Add-Member -NotePropertyName sourceDocuments -NotePropertyValue @(
  'PAV.SUPERIOR-Gran Tietê-Layout1.pdf'
) -Force
$map.floors[1].name = 'Piso superior - planta arquitetônica v11'

$groundZones = @($map.zones | Where-Object { $_.floor -eq 0 })
$upperZones = @(
  [pscustomobject]@{
    id = 'zone_upper_corridor'; name = 'Corredor do pavimento superior'; type = 'corridor_upper'
    floor = 1; x = 7.0; y = 43.0; width = 150.0; height = 10.0
    verification = 'floorplan'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_gate'; name = 'Portão Superior'; type = 'upper_entrance'
    floor = 1; x = 4.0; y = 43.0; width = 3.0; height = 10.0
    verification = 'user_confirmed'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_ramp'; name = 'Rampa para o térreo'; type = 'ramp'
    floor = 1; x = 7.0; y = 14.0; width = 10.0; height = 29.0
    verification = 'user_confirmed'; evidenceCaptureIds = @('capture_rampa_subida_181233')
  },
  [pscustomobject]@{
    id = 'zone_upper_van_gogh'; name = 'Van Gogh'; type = 'classroom'
    floor = 1; x = 8.0; y = 53.0; width = 13.5; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_cecilia'; name = 'Cecília Meireles'; type = 'classroom'
    floor = 1; x = 21.5; y = 53.0; width = 12.7; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_kaisen'; name = 'Laboratório Kaisen (Machado de Assis)'; type = 'classroom'
    floor = 1; x = 34.2; y = 53.0; width = 12.8; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_tarsila'; name = 'Tarsila do Amaral'; type = 'classroom'
    floor = 1; x = 47.0; y = 53.0; width = 12.8; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_auditorio'; name = 'Auditório'; type = 'auditorium'
    floor = 1; x = 59.8; y = 53.0; width = 25.5; height = 37.0
    verification = 'floorplan'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_bwc_fem'; name = 'BWC Feminino'; type = 'restroom'
    floor = 1; x = 85.3; y = 53.0; width = 8.1; height = 18.5
    verification = 'floorplan'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_bwc_masc'; name = 'BWC Masculino'; type = 'restroom'
    floor = 1; x = 85.3; y = 71.5; width = 8.1; height = 18.5
    verification = 'floorplan'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_monteiro'; name = 'Monteiro Lobato'; type = 'classroom'
    floor = 1; x = 93.4; y = 53.0; width = 12.1; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_fayol'; name = 'Fayol'; type = 'laboratory'
    floor = 1; x = 105.5; y = 53.0; width = 18.2; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_ayrton'; name = 'Ayrton Senna'; type = 'project_laboratory'
    floor = 1; x = 123.7; y = 53.0; width = 16.0; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_santos'; name = 'Santos Dummont'; type = 'classroom'
    floor = 1; x = 139.7; y = 53.0; width = 15.8; height = 37.0
    verification = 'floorplan_relative'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_archive'; name = 'Arquivo'; type = 'archive'
    floor = 1; x = 46.0; y = 8.0; width = 42.0; height = 8.0
    verification = 'floorplan'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_agronomy'; name = 'Área de Agronomia'; type = 'agronomy'
    floor = 1; x = 111.0; y = 10.0; width = 40.0; height = 25.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_area_agronomia_181639')
  }
)
$map.zones = @($groundZones + $upperZones)

function Set-DisplayPosition {
  param(
    [Parameter(Mandatory)] [object] $Node,
    [Parameter(Mandatory)] [double] $X,
    [Parameter(Mandatory)] [double] $Y
  )
  $Node | Add-Member -NotePropertyName displayX -NotePropertyValue $X -Force
  $Node | Add-Member -NotePropertyName displayY -NotePropertyValue $Y -Force
}

$map.nodes = @($map.nodes | Where-Object { $_.id -ne 'upper_construction' })
$newNodes = @(
  [pscustomobject]@{ id = 'upper_service_spine'; floor = 1; x = 84.0; y = 25.0; z = 1.0; type = 'corridor'; displayX = 89.35; displayY = 48.0 },
  [pscustomobject]@{ id = 'upper_archive_approach'; floor = 1; x = 40.0; y = 25.0; z = 1.0; type = 'corridor'; displayX = 66.0; displayY = 48.0 },
  [pscustomobject]@{ id = 'upper_bwc_fem'; floor = 1; x = 84.0; y = 19.0; z = 1.0; type = 'service'; displayX = 89.35; displayY = 62.25 },
  [pscustomobject]@{ id = 'upper_bwc_masc'; floor = 1; x = 84.0; y = 31.0; z = 1.0; type = 'service'; displayX = 89.35; displayY = 80.75 },
  [pscustomobject]@{ id = 'upper_archive'; floor = 1; x = 40.0; y = 8.0; z = 1.0; type = 'service'; displayX = 67.0; displayY = 12.0 }
)
$map.nodes = @($map.nodes + $newNodes)

$upperDisplay = @{
  upper_gate = @(5.5, 48.0)
  upper_spine_0 = @(14.75, 48.0)
  upper_spine_1 = @(27.85, 48.0)
  upper_spine_2 = @(40.60, 48.0)
  upper_spine_3 = @(53.40, 48.0)
  upper_spine_4 = @(72.55, 48.0)
  upper_spine_5 = @(99.45, 48.0)
  upper_spine_6 = @(114.60, 48.0)
  upper_spine_7 = @(131.70, 48.0)
  upper_spine_8 = @(147.60, 48.0)
  upper_door_0 = @(14.75, 58.0)
  upper_door_1 = @(27.85, 58.0)
  upper_door_2 = @(40.60, 58.0)
  upper_door_3 = @(53.40, 58.0)
  upper_door_4 = @(72.55, 58.0)
  upper_door_5 = @(99.45, 58.0)
  upper_door_6 = @(114.60, 58.0)
  upper_door_7 = @(131.70, 58.0)
  upper_door_8 = @(147.60, 58.0)
  upper_end = @(157.0, 48.0)
  upper_agronomy = @(132.0, 23.0)
  upper_ramp_approach = @(12.0, 43.0)
  upper_ramp_run_2 = @(12.0, 32.0)
  upper_spiral_ramp = @(12.0, 20.0)
}
foreach ($node in $map.nodes | Where-Object { $_.floor -eq 1 }) {
  if ($upperDisplay.ContainsKey($node.id)) {
    Set-DisplayPosition $node $upperDisplay[$node.id][0] $upperDisplay[$node.id][1]
  }
}

$map.pois = @($map.pois | Where-Object { $_.id -ne 'sala_em_construcao' })
$map.pois += @(
  [pscustomobject]@{
    id = 'bwc_feminino_superior'; name = 'BWC Feminino'; type = 'restroom'; sector = 'Piso Superior'
    floor = 1; x = 84.0; y = 19.0; z = 1.0; navigationNode = 'upper_bwc_fem'
    displayX = 89.35; displayY = 62.25; verification = 'floorplan'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'bwc_masculino_superior'; name = 'BWC Masculino'; type = 'restroom'; sector = 'Piso Superior'
    floor = 1; x = 84.0; y = 31.0; z = 1.0; navigationNode = 'upper_bwc_masc'
    displayX = 89.35; displayY = 80.75; verification = 'floorplan'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'arquivo_superior'; name = 'Arquivo'; type = 'archive'; sector = 'Piso Superior'
    floor = 1; x = 40.0; y = 8.0; z = 1.0; navigationNode = 'upper_archive'
    displayX = 67.0; displayY = 12.0; verification = 'floorplan'; evidenceCaptureIds = @()
  }
)

$nodeById = @{}
foreach ($node in $map.nodes) { $nodeById[$node.id] = $node }
$floorplanMappedPois = @(
  'van_gogh', 'cecilia_meireles', 'lab_kaisen_machado_assis',
  'tarsila_do_amaral', 'auditorio', 'monteiro_lobato', 'fayol',
  'ayrton_senna', 'santos_dummont'
)
foreach ($poi in $map.pois | Where-Object { $_.floor -eq 1 }) {
  $anchor = $nodeById[$poi.navigationNode]
  if ($null -ne $anchor) {
    $poi | Add-Member -NotePropertyName displayX -NotePropertyValue ([double]$anchor.displayX) -Force
    $poi | Add-Member -NotePropertyName displayY -NotePropertyValue ([double]$anchor.displayY) -Force
  }
  if ($floorplanMappedPois -contains $poi.id) {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'floorplan_relative' -Force
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  }
}
$map.pois | Where-Object { $_.id -eq 'portao_superior' } | ForEach-Object {
  $_ | Add-Member -NotePropertyName verification -NotePropertyValue 'user_confirmed' -Force
}
$map.pois | Where-Object { $_.id -eq 'rampa_caracol' } | ForEach-Object {
  $_.name = 'Rampa para o térreo'
  $_ | Add-Member -NotePropertyName verification -NotePropertyValue 'user_confirmed' -Force
}

$map.edges = @($map.edges | Where-Object {
  $_.from -notmatch '^upper_' -and $_.to -notmatch '^upper_'
})

function New-UpperEdge {
  param(
    [string] $From,
    [string] $To,
    [double] $Distance,
    [string] $Type = 'corridor',
    [bool] $Accessible = $true,
    [string] $Verification = 'floorplan'
  )
  [pscustomobject]@{
    from = $From; to = $To; distance = $Distance; type = $Type
    accessible = $Accessible; verification = $Verification; evidenceCaptureIds = @()
  }
}

$upperEdges = @(
  (New-UpperEdge 'upper_gate' 'upper_spine_0' 9.25 'entrance' $true 'user_confirmed'),
  (New-UpperEdge 'upper_spine_0' 'upper_spine_1' 13.10),
  (New-UpperEdge 'upper_spine_1' 'upper_spine_2' 12.75),
  (New-UpperEdge 'upper_spine_2' 'upper_spine_3' 12.80),
  (New-UpperEdge 'upper_spine_3' 'upper_archive_approach' 12.60),
  (New-UpperEdge 'upper_archive_approach' 'upper_spine_4' 6.55),
  (New-UpperEdge 'upper_spine_4' 'upper_service_spine' 16.80),
  (New-UpperEdge 'upper_service_spine' 'upper_spine_5' 10.10),
  (New-UpperEdge 'upper_spine_5' 'upper_spine_6' 15.15),
  (New-UpperEdge 'upper_spine_6' 'upper_spine_7' 17.10),
  (New-UpperEdge 'upper_spine_7' 'upper_spine_8' 15.90),
  (New-UpperEdge 'upper_spine_8' 'upper_end' 9.40),
  (New-UpperEdge 'upper_spine_0' 'upper_door_0' 10.0 'door'),
  (New-UpperEdge 'upper_spine_1' 'upper_door_1' 10.0 'door'),
  (New-UpperEdge 'upper_spine_2' 'upper_door_2' 10.0 'door'),
  (New-UpperEdge 'upper_spine_3' 'upper_door_3' 10.0 'door'),
  (New-UpperEdge 'upper_spine_4' 'upper_door_4' 10.0 'door'),
  (New-UpperEdge 'upper_spine_5' 'upper_door_5' 10.0 'door'),
  (New-UpperEdge 'upper_spine_6' 'upper_door_6' 10.0 'door'),
  (New-UpperEdge 'upper_spine_7' 'upper_door_7' 10.0 'door'),
  (New-UpperEdge 'upper_spine_8' 'upper_door_8' 10.0 'door'),
  (New-UpperEdge 'upper_service_spine' 'upper_bwc_fem' 14.25 'door'),
  (New-UpperEdge 'upper_service_spine' 'upper_bwc_masc' 32.75 'door'),
  (New-UpperEdge 'upper_archive_approach' 'upper_archive' 36.0 'open_area'),
  (New-UpperEdge 'upper_end' 'upper_agronomy' 34.7 'outdoor' $true 'observed_video'),
  (New-UpperEdge 'upper_ramp_approach' 'upper_spine_0' 4.2 'ramp_access' $true 'user_confirmed'),
  (New-UpperEdge 'upper_spiral_ramp' 'upper_ramp_run_2' 12.0 'ramp' $true 'observed_video'),
  (New-UpperEdge 'upper_ramp_run_2' 'upper_ramp_approach' 11.0 'ramp' $true 'observed_video'),
  (New-UpperEdge 'ground_ramp_landing_mid' 'upper_spiral_ramp' 9.0 'ramp' $true 'observed_video')
)
foreach ($edge in $upperEdges | Where-Object { $_.verification -eq 'observed_video' }) {
  $edge.evidenceCaptureIds = @(
    if ($edge.to -eq 'upper_agronomy') { 'capture_area_agronomia_181639' }
    else { 'capture_rampa_subida_181233' }
  )
}
$map.edges = @($map.edges + $upperEdges)

$json = $map | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($targetPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Planta superior v11 criada em $targetPath"
