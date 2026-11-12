export type MapFloorLike = {
  id?: string
  name?: string
  level: number
}

export type MapNodeLike = {
  id: string
  x: number
  y: number
  z?: number
  floor: number
  label?: string
  type?: string
}

export type MapEdgeLike = {
  id?: string
  from: string
  to: string
  type?: string
  accessible?: boolean
}

export type MapPoiLike = {
  id: string
  name: string
  x: number
  y: number
  z?: number
  floor: number
  sector?: string
  nodeId?: string
  navigationNode?: string
}

export type MapDataLike = {
  floors?: MapFloorLike[]
  nodes: MapNodeLike[]
  edges: MapEdgeLike[]
  pois: MapPoiLike[]
}

export type AuditLike = {
  id: number
  action: string
  details: string
  created_at: string
}

export type UserLookupLike = {
  id: number
  name: string
  email: string
}

export type AuditCategory = 'map' | 'academic' | 'community' | 'system'

export type FormattedAuditEntry = {
  category: AuditCategory
  categoryLabel: string
  title: string
  summary: string
  actor: string
  when: string
  rawAction: string
  rawDetails: string
  searchText: string
}

export type MapEdgeOption = {
  id: string
  from: string
  to: string
  floor: number
  floorName: string
  typeLabel: string
  label: string
  accessible: boolean
  searchText: string
}

export type MapNodeOption = {
  id: string
  floor: number
  floorName: string
  label: string
  group: 'poi' | 'corridor'
  poiName?: string
  sector?: string
  searchText: string
}

export function roleLabel(role: string): string {
  return {
    admin: 'Administrador',
    coordination: 'Coordenação',
    moderator: 'Moderador',
    professor: 'Professor',
    student: 'Aluno',
  }[role] ?? role
}

export function statusLabel(status: string): string {
  return {
    unverified: 'Não verificada',
    voting: 'Em votação',
    confirmed: 'Confirmada',
    contested: 'Contestada',
    rejected: 'Rejeitada',
  }[status] ?? status
}

export function closureStatusLabel(status: string): string {
  return {
    active: 'Bloqueado',
    resolved: 'Liberado',
  }[status] ?? status
}

export function edgeTypeLabel(type?: string): string {
  return {
    corridor: 'Corredor',
    ramp: 'Rampa',
    ramp_access: 'Acesso por rampa',
    door: 'Entrada de sala',
    entrance: 'Portaria / entrada',
    open_area: 'Área aberta',
    opening: 'Passagem',
    outdoor: 'Área externa',
    provisional_access: 'Acesso provisório',
    service_access: 'Acesso de serviço',
  }[type ?? ''] ?? 'Trecho'
}

export function parseAuditTimestamp(raw: string): Date | null {
  const value = raw.trim()
  if (!value) return null

  const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(value) &&
      !/[Zz]|[+-]\d{2}:?\d{2}$/.test(value)
    ? `${value.replace(' ', 'T')}Z`
    : value

  const parsed = new Date(normalized)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

export function formatAuditTimestamp(raw: string): string {
  const parsed = parseAuditTimestamp(raw)
  if (!parsed) return raw.trim() || '-'
  return parsed.toLocaleString('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  })
}

const NODE_TOKEN_LABELS: Record<string, string> = {
  ground: 'Térreo',
  upper: 'Piso superior',
  c1: 'Corredor Gran',
  c2: 'Corredor Tyto',
  spine: 'trecho',
  start: 'início',
  end: 'fim',
  first: 'trecho inicial',
  turn: 'curva',
  after: 'após',
  court: 'pátio central',
  west: 'oeste',
  east: 'leste',
  north: 'norte',
  south: 'sul',
  center: 'centro',
  mid: 'meio',
  spiral: 'espiral',
  ramp: 'rampa',
  landing: 'patamar',
  run: 'lance',
  approach: 'acesso',
  access: 'acesso',
  corner: 'esquina',
  gallery: 'galeria',
  step: 'degrau',
  bwc: 'banheiros',
  passage: 'passagem',
  open: 'área aberta',
  service: 'serviço',
  services: 'serviços',
  archive: 'arquivo',
  agronomy: 'Agronomia',
  snack: 'cantina',
  front: 'frente',
  labs: 'laboratórios',
  quimica: 'Química',
  entry: 'entrada',
  door: 'porta',
  gate: 'acesso principal',
  room: 'sala',
}

function humanizeNodeIdTokens(nodeId: string): string {
  const exact: Record<string, string> = {
    ground_c1_start: 'Início do corredor Gran',
    ground_c1_first: 'Trecho inicial do corredor Gran',
    ground_c1_turn: 'Curva do corredor Gran',
    ground_c1_after_turn: 'Corredor Gran (após a curva)',
    ground_c1_end: 'Fim do corredor Gran',
    ground_c2_end: 'Fim do corredor Tyto',
    ground_spiral_ramp_landing: 'Base da rampa espiral',
    ground_ramp_landing_mid: 'Patamar da rampa espiral',
    upper_ramp_approach: 'Acesso à rampa (piso superior)',
    upper_end: 'Fim do corredor superior',
    ground_snack_front: 'Frente da cantina',
    upper_bwc_passage: 'Passagem dos banheiros (superior)',
    upper_service_spine: 'Corredor de serviços (superior)',
    upper_archive_approach: 'Acesso ao arquivo (superior)',
    upper_agronomy_approach: 'Acesso à Agronomia (superior)',
    upper_south_access_corner: 'Esquina de acesso sul (superior)',
  }
  if (exact[nodeId]) return exact[nodeId]

  const c1Spine = /^ground_c1_spine_(\d+)$/.exec(nodeId)
  if (c1Spine) return `Corredor Gran · trecho ${Number(c1Spine[1]) + 1}`

  const c2Spine = /^ground_c2_spine_(\d+)$/.exec(nodeId)
  if (c2Spine) return `Corredor Tyto · trecho ${Number(c2Spine[1]) + 1}`

  const upperSpine = /^upper_spine_(\d+)$/.exec(nodeId)
  if (upperSpine) return `Corredor superior · trecho ${Number(upperSpine[1]) + 1}`

  const words = nodeId
    .split(/[_-]+/)
    .filter(Boolean)
    .map(token => {
      if (/^\d+$/.test(token)) return String(Number(token) + 1)
      return NODE_TOKEN_LABELS[token] ?? token
    })

  if (words.length === 0) return nodeId
  const text = words.join(' · ')
  return text.charAt(0).toUpperCase() + text.slice(1)
}

export function buildMapLookup(mapData: MapDataLike) {
  const floorNames = new Map<number, string>()
  for (const floor of mapData.floors ?? []) {
    if (floor.name) floorNames.set(floor.level, floor.name)
  }

  const floorLabel = (floor: number): string => {
    const known = floorNames.get(floor)
    if (known) return known
    if (floor === 0) return 'Térreo'
    if (floor === 1) return 'Piso superior'
    return `${floor}º andar`
  }

  const nodesById = new Map(mapData.nodes.map(node => [node.id, node]))
  const poiByNodeId = new Map<string, MapPoiLike>()
  for (const poi of mapData.pois ?? []) {
    const linked = (poi.navigationNode || poi.nodeId || '').trim()
    if (linked && !poiByNodeId.has(linked)) {
      poiByNodeId.set(linked, poi)
    }
  }

  const neighbors = new Map<string, Set<string>>()
  const ensureNeighbor = (a: string, b: string) => {
    let set = neighbors.get(a)
    if (!set) {
      set = new Set<string>()
      neighbors.set(a, set)
    }
    set.add(b)
  }
  for (const edge of mapData.edges ?? []) {
    ensureNeighbor(edge.from, edge.to)
    ensureNeighbor(edge.to, edge.from)
  }

  const nodeLabel = (nodeId: string): string => {
    const poi = poiByNodeId.get(nodeId)
    if (poi?.name) return poi.name
    const node = nodesById.get(nodeId)
    if (node?.label?.trim()) return node.label.trim()

    const base = humanizeNodeIdTokens(nodeId)
    const adjacentPoi = [...(neighbors.get(nodeId) ?? [])]
      .map(id => poiByNodeId.get(id)?.name)
      .find(Boolean)
    if (adjacentPoi && !base.toLowerCase().includes(adjacentPoi.toLowerCase())) {
      return `${base} (próx. ${adjacentPoi})`
    }
    return base
  }

  const edgeById = new Map<string, MapEdgeOption>()
  const edgeOptions: MapEdgeOption[] = (mapData.edges ?? []).map(edge => {
    const id = edge.id?.trim() || `${edge.from}__${edge.to}`
    const floor = nodesById.get(edge.from)?.floor ?? nodesById.get(edge.to)?.floor ?? 0
    const fName = floorLabel(floor)
    const tLabel = edgeTypeLabel(edge.type)
    const fromLabel = nodeLabel(edge.from)
    const toLabel = nodeLabel(edge.to)
    const label = `${tLabel}: ${fromLabel} → ${toLabel}`
    const option: MapEdgeOption = {
      id,
      from: edge.from,
      to: edge.to,
      floor,
      floorName: fName,
      typeLabel: tLabel,
      label,
      accessible: edge.accessible !== false,
      searchText: `${id} ${fName} ${tLabel} ${fromLabel} ${toLabel}`.toLocaleLowerCase('pt-BR'),
    }
    edgeById.set(id, option)
    return option
  })

  edgeOptions.sort((a, b) => a.floor - b.floor || a.label.localeCompare(b.label, 'pt-BR'))

  const edgeLabelById = (edgeId: string): string => {
    const known = edgeById.get(edgeId)
    if (known) return known.label
    const parts = edgeId.split('__')
    if (parts.length === 2) {
      return `${nodeLabel(parts[0])} → ${nodeLabel(parts[1])}`
    }
    return edgeId
  }

  const nodeOptions: MapNodeOption[] = (mapData.nodes ?? [])
    .map(node => {
      const poi = poiByNodeId.get(node.id)
      const fName = floorLabel(node.floor)
      const label = nodeLabel(node.id)
      return {
        id: node.id,
        floor: node.floor,
        floorName: fName,
        label,
        group: (poi ? 'poi' : 'corridor') as 'poi' | 'corridor',
        poiName: poi?.name,
        sector: poi?.sector,
        searchText: `${node.id} ${fName} ${label} ${poi?.sector ?? ''}`.toLocaleLowerCase('pt-BR'),
      }
    })
    .sort((a, b) => {
      if (a.group !== b.group) return a.group === 'poi' ? -1 : 1
      return a.floor - b.floor || a.label.localeCompare(b.label, 'pt-BR')
    })

  return {
    floors: [...new Set((mapData.nodes ?? []).map(n => n.floor))].sort((a, b) => a - b),
    floorLabel,
    nodeLabel,
    edgeLabelById,
    edgeById,
    edgeOptions,
    nodeOptions,
  }
}

type AuditMeta = {
  category: AuditCategory
  title: string
}

const AUDIT_CATEGORY_LABELS: Record<AuditCategory, string> = {
  map: 'Mapa e operação',
  academic: 'Acadêmico',
  community: 'Comunidade',
  system: 'Sistema e acessos',
}

const AUDIT_META: Record<string, AuditMeta> = {
  'course.created': { category: 'academic', title: 'Curso cadastrado' },
  'course.updated': { category: 'academic', title: 'Curso atualizado' },
  'course.deleted': { category: 'academic', title: 'Curso removido' },
  'subject.created': { category: 'academic', title: 'Disciplina cadastrada' },
  'subject.updated': { category: 'academic', title: 'Disciplina atualizada' },
  'subject.deleted': { category: 'academic', title: 'Disciplina removida' },
  'group.created': { category: 'academic', title: 'Turma cadastrada' },
  'group.updated': { category: 'academic', title: 'Turma atualizada' },
  'group.deleted': { category: 'academic', title: 'Turma removida' },
  'professor.created': { category: 'academic', title: 'Professor cadastrado' },
  'professor.updated': { category: 'academic', title: 'Professor atualizado' },
  'professor.deleted': { category: 'academic', title: 'Professor removido' },
  'room.created': { category: 'academic', title: 'Sala cadastrada' },
  'room.updated': { category: 'academic', title: 'Sala atualizada' },
  'room.deleted': { category: 'academic', title: 'Sala removida' },
  'schedule.created': { category: 'academic', title: 'Aula adicionada ao ensalamento' },
  'schedule.updated': { category: 'academic', title: 'Ensalamento atualizado' },
  'schedule.deleted': { category: 'academic', title: 'Aula removida do ensalamento' },
  'schedule.legacy_rooms_migrated': {
    category: 'academic',
    title: 'Salas antigas alinhadas ao mapa',
  },
  'map.version.created': { category: 'map', title: 'Nova revisão do mapa criada' },
  'map.version.updated': { category: 'map', title: 'Revisão do mapa editada' },
  'map.version.published': { category: 'map', title: 'Mapa publicado no app' },
  'map.version.deleted': { category: 'map', title: 'Rascunho de mapa excluído' },
  'navigation.closure.created': { category: 'map', title: 'Trecho interditado' },
  'navigation.closure.resolved': { category: 'map', title: 'Interdição liberada' },
  'positioning.anchor.created': { category: 'map', title: 'Ponto QR cadastrado' },
  'positioning.anchor.updated': { category: 'map', title: 'Ponto QR atualizado' },
  'positioning.anchor.disabled': { category: 'map', title: 'Ponto QR removido' },
  'positioning.fingerprints.created': { category: 'map', title: 'Calibração magnética enviada' },
  'proposal.created': { category: 'community', title: 'Nova sugestão de mudança de sala' },
  'proposal.voted': { category: 'community', title: 'Voto registrado em sugestão' },
  'proposal.moderated': { category: 'community', title: 'Sugestão moderada' },
  'proposal.applied': { category: 'community', title: 'Sugestão aplicada na grade oficial' },
  'user.role_updated': { category: 'system', title: 'Permissão de usuário alterada' },
  pc_bootstrap_completed_v1: { category: 'system', title: 'Importação inicial do banco' },
  'demo.seeded': { category: 'system', title: 'Base inicial de demonstração preparada' },
}

function summarizeBootstrapJson(details: string): string | null {
  if (!details.trim().startsWith('{')) return null
  try {
    const parsed = JSON.parse(details) as {
      imported_counts?: Record<string, number>
      version?: number
    }
    if (parsed.imported_counts) {
      const counts = parsed.imported_counts
      const parts: string[] = []
      if (typeof counts.rooms === 'number') parts.push(`${counts.rooms} salas`)
      if (typeof counts.schedules === 'number') parts.push(`${counts.schedules} aulas`)
      if (typeof counts.courses === 'number') parts.push(`${counts.courses} cursos`)
      if (typeof counts.users === 'number') parts.push(`${counts.users} usuários`)
      const totalTables = Object.values(counts).filter(v => Number(v) > 0).length
      return parts.length > 0
        ? `Dados importados para o PostgreSQL (${parts.join(', ')}; ${totalTables} tabelas).`
        : `Importação concluída (${totalTables} tabelas sincronizadas).`
    }
    return 'Configuração técnica registrada.'
  } catch {
    return null
  }
}

export function formatAuditEntry(
  item: AuditLike,
  options?: {
    usersById?: Map<number, UserLookupLike>
    usersByEmail?: Map<string, UserLookupLike>
    edgeLabelById?: (edgeId: string) => string
  },
): FormattedAuditEntry {
  const known = AUDIT_META[item.action] ?? (
    item.action.startsWith('demo.passwords')
      ? { category: 'system' as const, title: 'Senhas da demo atualizadas' }
      : {
          category: 'system' as const,
          title: item.action.replace(/[._]+/g, ' '),
        }
  )

  const when = formatAuditTimestamp(item.created_at)
  const raw = item.details ?? ''
  let summary = raw
  let actor = 'Sistema'

  const byActorMatch = /^(.*)\s+por\s+(\S+@\S+|\S+)$/.exec(raw.trim())
  if (byActorMatch) {
    const target = byActorMatch[1].trim()
    const rawActor = byActorMatch[2].trim()
    actor = options?.usersByEmail?.get(rawActor.toLowerCase())?.name ?? rawActor

    if (item.action === 'navigation.closure.created') {
      summary = `Trecho: ${options?.edgeLabelById ? options.edgeLabelById(target) : target}`
    } else if (item.action === 'navigation.closure.resolved') {
      summary = `Interdição ${target} encerrada`
    } else if (item.action.startsWith('map.version.')) {
      summary = target.startsWith('#') ? `Revisão ${target}` : `Versão ${target}`
    } else if (item.action.startsWith('positioning.anchor.')) {
      summary = target.startsWith('#') ? `Ponto QR ${target}` : `Código ${target}`
    } else {
      summary = target
    }
  } else {
    const jsonSummary = summarizeBootstrapJson(raw)
    if (jsonSummary) {
      summary = jsonSummary
      actor = 'Sistema'
    } else {
      const tupleMatch = /^(\d+):(\d+)(?::(.*))?$/.exec(raw.trim())
      if (tupleMatch) {
        const actorId = Number(tupleMatch[1])
        const entityId = Number(tupleMatch[2])
        const rest = tupleMatch[3] ?? ''
        actor = options?.usersById?.get(actorId)?.name ??
          options?.usersById?.get(actorId)?.email ??
          `Usuário #${actorId}`

        if (item.action === 'user.role_updated') {
          const targetUser = options?.usersById?.get(entityId)
          summary = `${targetUser ? targetUser.name : `Usuário #${entityId}`} → ${roleLabel(rest)}`
        } else if (item.action === 'proposal.voted') {
          const [agrees = '', nextStatus = ''] = rest.split(':')
          const voteText = agrees === 'True' || agrees === '1' || agrees === 'true'
            ? 'a favor'
            : 'contra'
          summary = `Sugestão #${entityId} • Voto ${voteText} • Situação: ${statusLabel(nextStatus)}`
        } else if (item.action === 'proposal.moderated') {
          summary = `Sugestão #${entityId} marcada como ${statusLabel(rest)}`
        } else if (item.action === 'proposal.applied') {
          const [scheduleId = '', roomId = ''] = rest.split(':')
          summary = `Sugestão #${entityId} aplicada na aula #${scheduleId} (sala #${roomId})`
        } else if (item.action.endsWith('.deleted')) {
          summary = `Registro #${entityId} removido`
        } else {
          summary = rest ? `${rest} (#${entityId})` : `Registro #${entityId}`
        }
      }
    }
  }

  const categoryLabel = AUDIT_CATEGORY_LABELS[known.category]
  const searchText = `${when} ${categoryLabel} ${known.title} ${summary} ${actor} ${item.action} ${raw}`
    .toLocaleLowerCase('pt-BR')

  return {
    category: known.category,
    categoryLabel,
    title: known.title,
    summary,
    actor,
    when,
    rawAction: item.action,
    rawDetails: raw,
    searchText,
  }
}
