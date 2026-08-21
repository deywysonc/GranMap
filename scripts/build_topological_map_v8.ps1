[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'app\assets\maps\gran_tiete_structural_v7.json'
$targetPath = Join-Path $root 'app\assets\maps\gran_tiete_topological_v8.json'
$map = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8 | ConvertFrom-Json

$map.building.version = '0.8-evidence-topology-v8'
$map.metadata.geometryStatus = 'topological'
$map.metadata.distanceStatus = 'provisional'
$map.metadata.coordinateSystem = 'navigation_conceptual_xyz_with_independent_topology_xy'
$map.metadata.distanceUnit = 'conceptual_unit'
$map.metadata.surveyStatus = 'four_walkthroughs_partially_mapped'
$map.metadata.importantNote = 'Mapa topológico, sem escala: traços contínuos representam percursos vistos nos vídeos; traços interrompidos e caixas pontilhadas representam relações informadas ou posições ainda não localizadas. O desenho não é uma planta baixa.'
$map.metadata | Add-Member -NotePropertyName mapMode -NotePropertyValue 'evidence_topology' -Force
$map.metadata | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @(
  'capture_entrada_gran_180941',
  'capture_rampa_subida_181233',
  'capture_area_agronomia_181639',
  'capture_corredor_entrada_tyto_182059'
) -Force

$map.floors[0].name = 'Térreo — mapa topológico'
$map.floors[1].name = 'Piso superior — mapa topológico'

$map.zones = @(
  [pscustomobject]@{
    id = 'zone_ground_c1'; name = 'Circulação da Entrada Gran'; type = 'corridor_gran'
    floor = 0; x = 4.0; y = 54.0; width = 92.0; height = 40.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_entrada_gran_180941')
  },
  [pscustomobject]@{
    id = 'zone_ground_c2'; name = 'Corredor da Entrada Tyto + Secretaria'; type = 'corridor_tyto'
    floor = 0; x = 114.0; y = 8.0; width = 30.0; height = 86.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_corredor_entrada_tyto_182059')
  },
  [pscustomobject]@{
    id = 'zone_ground_unlocated'; name = 'Demais locais do térreo'; type = 'unlocated_group'
    floor = 0; x = 82.0; y = 8.0; width = 28.0; height = 48.0
    verification = 'unlocated'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_walkway'; name = 'Galeria coberta no topo da rampa'; type = 'upper_walkway'
    floor = 1; x = 48.0; y = 55.0; width = 74.0; height = 37.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_rampa_subida_181233')
  },
  [pscustomobject]@{
    id = 'zone_upper_ramp'; name = 'Rampa em lances'; type = 'ramp'
    floor = 1; x = 96.0; y = 8.0; width = 24.0; height = 40.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_rampa_subida_181233')
  },
  [pscustomobject]@{
    id = 'zone_upper_agronomy'; name = 'Área de Agronomia'; type = 'agronomy'
    floor = 1; x = 126.0; y = 55.0; width = 22.0; height = 37.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_area_agronomia_181639')
  },
  [pscustomobject]@{
    id = 'zone_upper_unlocated'; name = 'Salas e portão do piso superior'; type = 'unlocated_group'
    floor = 1; x = 5.0; y = 8.0; width = 85.0; height = 40.0
    verification = 'unlocated'; evidenceCaptureIds = @()
  }
)

function Set-DisplayPosition {
  param(
    [Parameter(Mandatory)] [object] $Node,
    [Parameter(Mandatory)] [double] $X,
    [Parameter(Mandatory)] [double] $Y
  )
  $Node | Add-Member -NotePropertyName displayX -NotePropertyValue $X -Force
  $Node | Add-Member -NotePropertyName displayY -NotePropertyValue $Y -Force
}

foreach ($node in $map.nodes) {
  switch -Regex ($node.id) {
    '^ground_c1_start$' { Set-DisplayPosition $node 8 72; continue }
    '^ground_c1_first$' { Set-DisplayPosition $node 17 72; continue }
    '^ground_c1_room_ramp$' { Set-DisplayPosition $node 18 84; continue }
    '^ground_c1_turn$' { Set-DisplayPosition $node 25 72; continue }
    '^ground_c1_after_turn$' { Set-DisplayPosition $node 31 68; continue }
    '^ground_c1_spine_(\d+)$' {
      Set-DisplayPosition $node (40 + 10 * [int]$Matches[1]) 68
      continue
    }
    '^ground_c1_door_(\d+)$' {
      Set-DisplayPosition $node (40 + 10 * [int]$Matches[1]) 59
      continue
    }
    '^ground_c1_end$' { Set-DisplayPosition $node 96 68; continue }
    '^ground_c2_start$' { Set-DisplayPosition $node 126 90; continue }
    '^ground_secretaria_door$' { Set-DisplayPosition $node 137 83; continue }
    '^ground_c2_spine_(\d+)$' {
      Set-DisplayPosition $node 126 (82 - 5.7 * [int]$Matches[1])
      continue
    }
    '^ground_c2_door_(\d+)$' {
      $index = [int]$Matches[1]
      $sideX = if (($index % 2) -eq 0) { 118.0 } else { 135.0 }
      Set-DisplayPosition $node $sideX (82 - 5.7 * $index)
      continue
    }
    '^ground_c2_end$' { Set-DisplayPosition $node 126 12; continue }
    '^ground_court_west_north$' { Set-DisplayPosition $node 88 50; continue }
    '^ground_court_west_mid$' { Set-DisplayPosition $node 94 43; continue }
    '^ground_court_west_south$' { Set-DisplayPosition $node 101 48; continue }
    '^ground_court_east_north$' { Set-DisplayPosition $node 89 35; continue }
    '^ground_court_east_south$' { Set-DisplayPosition $node 101 35; continue }
    '^ground_snack_bar$' { Set-DisplayPosition $node 88 27; continue }
    '^ground_services_north$' { Set-DisplayPosition $node 102 28; continue }
    '^ground_services_mid$' { Set-DisplayPosition $node 102 21; continue }
    '^ground_services_south$' { Set-DisplayPosition $node 102 14; continue }
    '^ground_spiral_ramp_landing$' { Set-DisplayPosition $node 91 11; continue }
    '^ground_ramp_run_1$' { Set-DisplayPosition $node 91 18; continue }
    '^ground_ramp_landing_mid$' { Set-DisplayPosition $node 91 25; continue }
    '^upper_gate$' { Set-DisplayPosition $node 8 28; continue }
    '^upper_spine_(\d+)$' {
      Set-DisplayPosition $node (16 + 8 * [int]$Matches[1]) 28
      continue
    }
    '^upper_door_(\d+)$' {
      $index = [int]$Matches[1]
      $doorY = if (($index % 2) -eq 0) { 40.0 } else { 16.0 }
      Set-DisplayPosition $node (16 + 8 * $index) $doorY
      continue
    }
    '^upper_end$' { Set-DisplayPosition $node 88 70; continue }
    '^upper_construction$' { Set-DisplayPosition $node 48 11; continue }
    '^upper_agronomy$' { Set-DisplayPosition $node 137 72; continue }
    '^upper_ramp_approach$' { Set-DisplayPosition $node 101 70; continue }
    '^upper_ramp_run_2$' { Set-DisplayPosition $node 108 30; continue }
    '^upper_spiral_ramp$' { Set-DisplayPosition $node 108 58; continue }
    default { Set-DisplayPosition $node ([double]$node.x) ([double]$node.y) }
  }
}

$nodeById = @{}
foreach ($node in $map.nodes) { $nodeById[$node.id] = $node }

$observedPois = @{
  entrada_gran = 'capture_entrada_gran_180941'
  entrada_tyto_gran = 'capture_corredor_entrada_tyto_182059'
  area_agronomia = 'capture_area_agronomia_181639'
  rampa_caracol = 'capture_rampa_subida_181233'
}

foreach ($poi in $map.pois) {
  $anchor = $nodeById[$poi.navigationNode]
  $poi | Add-Member -NotePropertyName displayX -NotePropertyValue ([double]$anchor.displayX) -Force
  $poi | Add-Member -NotePropertyName displayY -NotePropertyValue ([double]$anchor.displayY) -Force
  if ($observedPois.ContainsKey($poi.id)) {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'observed_video' -Force
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @($observedPois[$poi.id]) -Force
  } elseif ($poi.id -eq 'secretaria') {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'user_reported' -Force
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @('capture_corredor_entrada_tyto_182059') -Force
  } else {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'unlocated' -Force
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  }
}

function Test-ObservedEdge {
  param([object] $Edge)
  if ($Edge.from -match '^ground_c1_(start|first|turn|after_turn|spine_\d+)$' -and
      $Edge.to -match '^ground_c1_(first|turn|after_turn|spine_\d+|end)$' -and
      $Edge.type -eq 'corridor') { return 'capture_entrada_gran_180941' }
  if ($Edge.from -match '^ground_c2_(start|spine_\d+)$' -and
      $Edge.to -match '^ground_c2_(spine_\d+|end)$' -and
      $Edge.type -eq 'corridor') { return 'capture_corredor_entrada_tyto_182059' }
  if (($Edge.from -eq 'upper_end' -and $Edge.to -eq 'upper_ramp_approach') -or
      ($Edge.from -eq 'upper_ramp_approach' -and $Edge.to -eq 'upper_spiral_ramp')) {
    return 'capture_rampa_subida_181233'
  }
  if ($Edge.type -eq 'ramp' -and
      ($Edge.from -match '^(ground_spiral_ramp_landing|ground_ramp_run_1|ground_ramp_landing_mid|upper_ramp_run_2)$')) {
    return 'capture_rampa_subida_181233'
  }
  return $null
}

foreach ($edge in $map.edges) {
  $captureId = Test-ObservedEdge $edge
  if ($captureId) {
    $edge | Add-Member -NotePropertyName verification -NotePropertyValue 'observed_video' -Force
    $edge | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @($captureId) -Force
  } else {
    $edge | Add-Member -NotePropertyName verification -NotePropertyValue 'unlocated' -Force
    $edge | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  }
}

$json = $map | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($targetPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Mapa topológico criado em $targetPath"
