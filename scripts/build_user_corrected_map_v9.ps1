[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'app\assets\maps\gran_tiete_structural_v7.json'
$targetPath = Join-Path $root 'app\assets\maps\gran_tiete_user_corrected_v9.json'
$map = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8 | ConvertFrom-Json

$map.building.version = '0.9-user-corrected-v9'
$map.metadata.geometryStatus = 'topological'
$map.metadata.distanceStatus = 'provisional'
$map.metadata.coordinateSystem = 'navigation_conceptual_xyz_with_independent_topology_xy'
$map.metadata.distanceUnit = 'conceptual_unit'
$map.metadata.surveyStatus = 'four_walkthroughs_plus_author_spatial_corrections'
$map.metadata.importantNote = 'Mapa sem escala corrigido com observações do autor: Entrada Gran em faixa horizontal, Tyto em eixo lateral, quadra à frente dos dois corredores, lanchonete e acesso superior à esquerda da Entrada Gran, sala com rampa à direita da curva e Portão Superior na lateral esquerda da circulação superior.'
$map.metadata | Add-Member -NotePropertyName mapMode -NotePropertyValue 'user_corrected_topology' -Force
$map.metadata | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @(
  'capture_entrada_gran_180941',
  'capture_rampa_subida_181233',
  'capture_area_agronomia_181639',
  'capture_corredor_entrada_tyto_182059'
) -Force

$map.floors[0].name = 'Térreo — mapa corrigido'
$map.floors[1].name = 'Piso superior — mapa corrigido'

$map.zones = @(
  [pscustomobject]@{
    id = 'zone_ground_c1'; name = 'Circulação da Entrada Gran'; type = 'corridor_gran'
    floor = 0; x = 20.0; y = 54.0; width = 92.0; height = 40.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_entrada_gran_180941')
  },
  [pscustomobject]@{
    id = 'zone_ground_c2'; name = 'Corredor da Entrada Tyto + Secretaria'; type = 'corridor_tyto'
    floor = 0; x = 116.0; y = 8.0; width = 30.0; height = 86.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_corredor_entrada_tyto_182059')
  },
  [pscustomobject]@{
    id = 'zone_ground_court'; name = 'Quadra — à frente dos corredores'; type = 'court'
    floor = 0; x = 78.0; y = 8.0; width = 34.0; height = 42.0
    verification = 'user_confirmed'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_ground_snack'; name = 'Lanchonete'; type = 'cafeteria'
    floor = 0; x = 4.0; y = 62.0; width = 14.0; height = 20.0
    verification = 'user_confirmed'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_ground_upper_access'; name = 'Acesso ao piso superior'; type = 'ramp'
    floor = 0; x = 4.0; y = 34.0; width = 14.0; height = 22.0
    verification = 'user_confirmed'; evidenceCaptureIds = @('capture_rampa_subida_181233')
  },
  [pscustomobject]@{
    id = 'zone_ground_services'; name = 'Biblioteca • Financeiro • Banheiros'; type = 'services'
    floor = 0; x = 48.0; y = 8.0; width = 26.0; height = 42.0
    verification = 'user_reported'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_upper_gate'; name = 'Portão Superior'; type = 'upper_entrance'
    floor = 1; x = 32.0; y = 60.0; width = 14.0; height = 22.0
    verification = 'user_confirmed'; evidenceCaptureIds = @()
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
    id = 'zone_upper_unlocated'; name = 'Salas do piso superior'; type = 'unlocated_group'
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
    '^ground_c1_start$' { Set-DisplayPosition $node 22 72; continue }
    '^ground_c1_first$' { Set-DisplayPosition $node 30 72; continue }
    '^ground_c1_room_ramp$' { Set-DisplayPosition $node 44 83; continue }
    '^ground_c1_turn$' { Set-DisplayPosition $node 38 68; continue }
    '^ground_c1_after_turn$' { Set-DisplayPosition $node 44 68; continue }
    '^ground_c1_spine_(\d+)$' {
      Set-DisplayPosition $node (52 + 10 * [int]$Matches[1]) 68
      continue
    }
    '^ground_c1_door_(\d+)$' {
      Set-DisplayPosition $node (52 + 10 * [int]$Matches[1]) 59
      continue
    }
    '^ground_c1_end$' { Set-DisplayPosition $node 112 68; continue }
    '^ground_c2_start$' { Set-DisplayPosition $node 130 90; continue }
    '^ground_secretaria_door$' { Set-DisplayPosition $node 141 83; continue }
    '^ground_c2_spine_(\d+)$' {
      Set-DisplayPosition $node 130 (82 - 5.7 * [int]$Matches[1])
      continue
    }
    '^ground_c2_door_(\d+)$' {
      $index = [int]$Matches[1]
      $sideX = if (($index % 2) -eq 0) { 121.0 } else { 140.0 }
      Set-DisplayPosition $node $sideX (82 - 5.7 * $index)
      continue
    }
    '^ground_c2_end$' { Set-DisplayPosition $node 130 12; continue }
    '^ground_court_west_north$' { Set-DisplayPosition $node 104 49; continue }
    '^ground_court_west_mid$' { Set-DisplayPosition $node 95 39; continue }
    '^ground_court_west_south$' { Set-DisplayPosition $node 112 18; continue }
    '^ground_court_east_north$' { Set-DisplayPosition $node 106 37; continue }
    '^ground_court_east_south$' { Set-DisplayPosition $node 106 20; continue }
    '^ground_snack_bar$' { Set-DisplayPosition $node 11 70; continue }
    '^ground_services_north$' { Set-DisplayPosition $node 61 38; continue }
    '^ground_services_mid$' { Set-DisplayPosition $node 61 29; continue }
    '^ground_services_south$' { Set-DisplayPosition $node 61 20; continue }
    '^ground_spiral_ramp_landing$' { Set-DisplayPosition $node 11 38; continue }
    '^ground_ramp_run_1$' { Set-DisplayPosition $node 11 45; continue }
    '^ground_ramp_landing_mid$' { Set-DisplayPosition $node 11 52; continue }
    '^upper_gate$' { Set-DisplayPosition $node 44 70; continue }
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
$userConfirmedPois = @(
  'rampa_acesso_sala',
  'secretaria',
  'lanchonete',
  'quadra',
  'portao_superior'
)

foreach ($poi in $map.pois) {
  $anchor = $nodeById[$poi.navigationNode]
  $poi | Add-Member -NotePropertyName displayX -NotePropertyValue ([double]$anchor.displayX) -Force
  $poi | Add-Member -NotePropertyName displayY -NotePropertyValue ([double]$anchor.displayY) -Force
  if ($observedPois.ContainsKey($poi.id)) {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'observed_video' -Force
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @($observedPois[$poi.id]) -Force
  } elseif ($userConfirmedPois -contains $poi.id) {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'user_confirmed' -Force
    $poiEvidence = if ($poi.id -eq 'secretaria') { @('capture_corredor_entrada_tyto_182059') } else { @() }
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @($poiEvidence) -Force
  } elseif ($poi.floor -eq 0) {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'user_reported' -Force
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  } else {
    $poi | Add-Member -NotePropertyName verification -NotePropertyValue 'unlocated' -Force
    $poi | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  }
}

$map.edges = @($map.edges | Where-Object {
  -not (
    ($_.from -eq 'ground_court_west_north' -and $_.to -eq 'ground_snack_bar') -or
    ($_.from -eq 'ground_services_south' -and $_.to -eq 'ground_spiral_ramp_landing') -or
    ($_.from -eq 'upper_gate' -and $_.to -eq 'upper_spine_0')
  )
})
$map.edges += @(
  [pscustomobject]@{
    from = 'ground_c1_start'; to = 'ground_snack_bar'; distance = 7.5
    type = 'service_access'; accessible = $true
  },
  [pscustomobject]@{
    from = 'ground_c1_start'; to = 'ground_spiral_ramp_landing'; distance = 8.0
    type = 'ramp_access'; accessible = $true
  },
  [pscustomobject]@{
    from = 'upper_gate'; to = 'upper_end'; distance = 12.0
    type = 'corridor'; accessible = $true
  }
)

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

function Test-UserConfirmedEdge {
  param([object] $Edge)
  $key = "$($Edge.from)__$($Edge.to)"
  if ($key -in @(
      'ground_c1_first__ground_c1_room_ramp',
      'ground_c1_end__ground_court_west_north',
      'ground_c2_end__ground_court_west_south',
      'ground_c1_start__ground_snack_bar',
      'ground_c1_start__ground_spiral_ramp_landing',
      'upper_gate__upper_end'
    )) { return $true }
  if ($Edge.type -eq 'open_area' -and
      $Edge.from -match '^ground_court_' -and
      $Edge.to -match '^ground_court_') { return $true }
  return $false
}

foreach ($edge in $map.edges) {
  $captureId = Test-ObservedEdge $edge
  if ($captureId) {
    $edge | Add-Member -NotePropertyName verification -NotePropertyValue 'observed_video' -Force
    $edge | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @($captureId) -Force
  } elseif (Test-UserConfirmedEdge $edge) {
    $edge | Add-Member -NotePropertyName verification -NotePropertyValue 'user_confirmed' -Force
    $edge | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  } elseif ($nodeById[$edge.from].floor -eq 0 -and $nodeById[$edge.to].floor -eq 0) {
    $edge | Add-Member -NotePropertyName verification -NotePropertyValue 'user_reported' -Force
    $edge | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  } else {
    $edge | Add-Member -NotePropertyName verification -NotePropertyValue 'unlocated' -Force
    $edge | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @() -Force
  }
}

$json = $map | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($targetPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Mapa corrigido criado em $targetPath"
