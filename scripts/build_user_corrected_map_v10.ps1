[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'app\assets\maps\gran_tiete_structural_v7.json'
$targetPath = Join-Path $root 'app\assets\maps\gran_tiete_user_corrected_v10.json'
$map = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8 | ConvertFrom-Json

$map.building.version = '0.10-user-corrected-v10'
$map.metadata.geometryStatus = 'topological'
$map.metadata.distanceStatus = 'provisional'
$map.metadata.coordinateSystem = 'navigation_conceptual_xyz_with_independent_topology_xy'
$map.metadata.distanceUnit = 'conceptual_unit'
$map.metadata.surveyStatus = 'four_walkthroughs_plus_author_floorplan_corrections_v10'
$map.metadata.importantNote = 'Mapa sem escala corrigido com as marcações do autor: os corredores Entrada Gran e Tyto/Secretaria são paralelos; a quadra fica depois dos dois corredores; Biblioteca, Financeiro e Banheiros ficam do outro lado da quadra; Lanchonete e entrada da rampa ficam juntas na extremidade direita do corredor Gran; a sala com rampa fica à direita da curva; e o Portão Superior fica na lateral esquerda da circulação superior.'
$map.metadata | Add-Member -NotePropertyName mapMode -NotePropertyValue 'author_corrected_floorplan_topology' -Force
$map.metadata | Add-Member -NotePropertyName evidenceCaptureIds -NotePropertyValue @(
  'capture_entrada_gran_180941',
  'capture_rampa_subida_181233',
  'capture_area_agronomia_181639',
  'capture_corredor_entrada_tyto_182059'
) -Force

$map.floors[0].name = 'Térreo — planta corrigida v10'
$map.floors[1].name = 'Piso superior — planta corrigida v10'

$map.zones = @(
  [pscustomobject]@{
    id = 'zone_ground_c1'; name = 'Circulação da Entrada Gran'; type = 'corridor_gran'
    floor = 0; x = 4.0; y = 56.0; width = 100.0; height = 38.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_entrada_gran_180941')
  },
  [pscustomobject]@{
    id = 'zone_ground_c2'; name = 'Corredor da Entrada Tyto + Secretaria'; type = 'corridor_tyto'
    floor = 0; x = 4.0; y = 8.0; width = 100.0; height = 38.0
    verification = 'observed_video'; evidenceCaptureIds = @('capture_corredor_entrada_tyto_182059')
  },
  [pscustomobject]@{
    id = 'zone_ground_court'; name = 'Quadra — depois dos dois corredores'; type = 'court'
    floor = 0; x = 108.0; y = 18.0; width = 26.0; height = 50.0
    verification = 'user_confirmed'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_ground_snack'; name = 'Lanchonete'; type = 'cafeteria'
    floor = 0; x = 106.0; y = 74.0; width = 14.0; height = 18.0
    verification = 'user_confirmed'; evidenceCaptureIds = @()
  },
  [pscustomobject]@{
    id = 'zone_ground_upper_access'; name = 'Entrada da rampa para o piso superior'; type = 'ramp'
    floor = 0; x = 122.0; y = 74.0; width = 14.0; height = 18.0
    verification = 'user_confirmed'; evidenceCaptureIds = @('capture_rampa_subida_181233')
  },
  [pscustomobject]@{
    id = 'zone_ground_services'; name = 'Biblioteca • Financeiro • Banheiros — outro lado da quadra'; type = 'services'
    floor = 0; x = 138.0; y = 18.0; width = 18.0; height = 50.0
    verification = 'user_confirmed'; evidenceCaptureIds = @()
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
    '^ground_c1_start$' { Set-DisplayPosition $node 8 74; continue }
    '^ground_c1_first$' { Set-DisplayPosition $node 16 74; continue }
    '^ground_c1_room_ramp$' { Set-DisplayPosition $node 30 83; continue }
    '^ground_c1_turn$' { Set-DisplayPosition $node 24 70; continue }
    '^ground_c1_after_turn$' { Set-DisplayPosition $node 30 70; continue }
    '^ground_c1_spine_(\d+)$' {
      Set-DisplayPosition $node (40 + 11.5 * [int]$Matches[1]) 70
      continue
    }
    '^ground_c1_door_(\d+)$' {
      Set-DisplayPosition $node (40 + 11.5 * [int]$Matches[1]) 61
      continue
    }
    '^ground_c1_end$' { Set-DisplayPosition $node 104 70; continue }
    '^ground_c2_start$' { Set-DisplayPosition $node 8 28; continue }
    '^ground_secretaria_door$' { Set-DisplayPosition $node 14 39; continue }
    '^ground_c2_spine_(\d+)$' {
      Set-DisplayPosition $node (20 + 7 * [int]$Matches[1]) 28
      continue
    }
    '^ground_c2_door_(\d+)$' {
      $index = [int]$Matches[1]
      $sideY = if (($index % 2) -eq 0) { 39.0 } else { 17.0 }
      Set-DisplayPosition $node (20 + 7 * $index) $sideY
      continue
    }
    '^ground_c2_end$' { Set-DisplayPosition $node 104 28; continue }
    '^ground_court_west_north$' { Set-DisplayPosition $node 110 62; continue }
    '^ground_court_west_mid$' { Set-DisplayPosition $node 110 43; continue }
    '^ground_court_west_south$' { Set-DisplayPosition $node 110 24; continue }
    '^ground_court_east_north$' { Set-DisplayPosition $node 132 62; continue }
    '^ground_court_east_south$' { Set-DisplayPosition $node 132 24; continue }
    '^ground_snack_bar$' { Set-DisplayPosition $node 113 82; continue }
    '^ground_services_north$' { Set-DisplayPosition $node 146 58; continue }
    '^ground_services_mid$' { Set-DisplayPosition $node 146 43; continue }
    '^ground_services_south$' { Set-DisplayPosition $node 146 28; continue }
    '^ground_spiral_ramp_landing$' { Set-DisplayPosition $node 129 82; continue }
    '^ground_ramp_run_1$' { Set-DisplayPosition $node 129 78; continue }
    '^ground_ramp_landing_mid$' { Set-DisplayPosition $node 129 74; continue }
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
    from = 'ground_c1_end'; to = 'ground_snack_bar'; distance = 7.5
    type = 'service_access'; accessible = $true
  },
  [pscustomobject]@{
    from = 'ground_c1_end'; to = 'ground_spiral_ramp_landing'; distance = 8.0
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
      'ground_c1_end__ground_snack_bar',
      'ground_c1_end__ground_spiral_ramp_landing',
      'ground_court_east_north__ground_services_north',
      'ground_services_south__ground_court_east_south',
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
