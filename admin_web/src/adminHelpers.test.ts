import { describe, expect, it } from 'vitest'
import {
  buildMapLookup,
  closureStatusLabel,
  formatAuditEntry,
  formatAuditTimestamp,
  parseAuditTimestamp,
} from './adminHelpers'

const SAMPLE_MAP = {
  floors: [
    { id: 'floor_0', name: 'Térreo', level: 0 },
    { id: 'floor_1', name: 'Piso superior', level: 1 },
  ],
  nodes: [
    { id: 'ground_c1_start', x: 0, y: 32, floor: 0, type: 'entrance' },
    { id: 'ground_c1_first', x: 8, y: 32, floor: 0, type: 'corridor' },
    { id: 'ground_c1_room_ramp', x: 10, y: 26, floor: 0, type: 'ramp' },
    { id: 'upper_spine_0', x: 12, y: 30, floor: 1, type: 'corridor' },
  ],
  edges: [
    { from: 'ground_c1_start', to: 'ground_c1_first', type: 'corridor', accessible: true },
    { from: 'ground_c1_first', to: 'ground_c1_room_ramp', type: 'ramp_access', accessible: true },
  ],
  pois: [
    {
      id: 'entrada_gran',
      name: 'Entrada Gran',
      x: 0,
      y: 32,
      floor: 0,
      sector: 'Corredor Entrada Gran',
      navigationNode: 'ground_c1_start',
    },
    {
      id: 'rampa_acesso_sala',
      name: 'Sala com rampa de acesso',
      x: 10,
      y: 26,
      floor: 0,
      sector: 'Corredor Entrada Gran',
      navigationNode: 'ground_c1_room_ramp',
    },
  ],
}

describe('adminHelpers', () => {
  it('interpreta datas ISO do PostgreSQL e SQLite sem retornar Invalid Date', () => {
    const pgIso = parseAuditTimestamp('2026-11-12T11:48:00+00:00')
    const sqliteNaive = parseAuditTimestamp('2026-11-12 11:48:00')

    expect(pgIso).not.toBeNull()
    expect(sqliteNaive).not.toBeNull()
    expect(pgIso?.toISOString()).toBe('2026-11-12T11:48:00.000Z')
    expect(sqliteNaive?.toISOString()).toBe('2026-11-12T11:48:00.000Z')
    expect(formatAuditTimestamp('2026-11-12T11:48:00+00:00')).not.toContain('Invalid')
  })

  it('traduz nós, pisos e trechos do mapa para nomes legíveis', () => {
    const lookup = buildMapLookup(SAMPLE_MAP)

    expect(lookup.floorLabel(0)).toBe('Térreo')
    expect(lookup.floorLabel(1)).toBe('Piso superior')
    expect(lookup.nodeLabel('ground_c1_start')).toBe('Entrada Gran')
    expect(lookup.nodeLabel('ground_c1_first')).toContain('Trecho inicial do corredor Gran')
    expect(lookup.edgeLabelById('ground_c1_first__ground_c1_room_ramp')).toContain(
      'Acesso por rampa:',
    )
    expect(lookup.edgeLabelById('ground_c1_first__ground_c1_room_ramp')).toContain(
      'Sala com rampa de acesso',
    )
    expect(closureStatusLabel('active')).toBe('Bloqueado')
    expect(closureStatusLabel('resolved')).toBe('Liberado')
  })

  it('formata registros de auditoria para leitura humana', () => {
    const lookup = buildMapLookup(SAMPLE_MAP)
    const usersById = new Map([
      [1, { id: 1, name: 'Ana Admin', email: 'admin@granmap.local' }],
      [5, { id: 5, name: 'Carlos Coordenador', email: 'carlos@granmap.local' }],
    ])
    const usersByEmail = new Map([
      ['admin@granmap.local', { id: 1, name: 'Ana Admin', email: 'admin@granmap.local' }],
    ])

    const closureEntry = formatAuditEntry(
      {
        id: 10,
        action: 'navigation.closure.created',
        details: 'ground_c1_first__ground_c1_room_ramp por admin@granmap.local',
        created_at: '2026-11-12T11:48:00+00:00',
      },
      { usersById, usersByEmail, edgeLabelById: lookup.edgeLabelById },
    )
    expect(closureEntry.category).toBe('map')
    expect(closureEntry.title).toBe('Trecho interditado')
    expect(closureEntry.summary).toContain('Sala com rampa de acesso')
    expect(closureEntry.actor).toBe('Ana Admin')

    const bootstrapEntry = formatAuditEntry({
      id: 1,
      action: 'pc_bootstrap_completed_v1',
      details: JSON.stringify({
        imported_counts: { courses: 3, rooms: 27, schedules: 15, users: 4 },
        source_sha256: 'abc',
        version: 1,
      }),
      created_at: '2026-11-12 10:00:00',
    })
    expect(bootstrapEntry.title).toBe('Importação inicial do banco')
    expect(bootstrapEntry.summary).toContain('27 salas, 15 aulas, 3 cursos, 4 usuários')
    expect(bootstrapEntry.summary).not.toContain('source_sha256')

    const roleEntry = formatAuditEntry(
      {
        id: 11,
        action: 'user.role_updated',
        details: '1:5:moderator',
        created_at: '2026-11-12T12:00:00Z',
      },
      { usersById },
    )
    expect(roleEntry.title).toBe('Permissão de usuário alterada')
    expect(roleEntry.summary).toBe('Carlos Coordenador → Moderador')
    expect(roleEntry.actor).toBe('Ana Admin')
  })
})
