import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { ErrorBoundary } from './ErrorBoundary'
import {
  ApiError,
  deleteJson,
  getJson,
  hasAdminSession,
  postJson,
  putJson,
  request,
} from './api'
import {
  type AuditCategory,
  buildMapLookup,
  closureStatusLabel,
  formatAuditEntry,
  formatAuditTimestamp,
  roleLabel,
  statusLabel,
} from './adminHelpers'
import './styles.css'

type Course = { id: number; name: string }
type Professor = { id: number; name: string; email: string }
type Room = { id: number; poi_id: string; name: string; floor: number; building: string }
type Subject = { id: number; course_id: number; course_name: string; name: string }
type AcademicGroup = {
  id: number
  course_id: number
  course_name: string
  semester: number
  name: string
}
type User = {
  id: number
  name: string
  email: string
  role: string
  reputation: number
  course_name?: string
  semester?: number
  group_name?: string
  created_at?: string
}
type AuthResult = { user: User; csrf_token?: string; token?: string }
type Schedule = {
  id: number
  course_id: number
  professor_id?: number
  room_id: number
  course_name: string
  semester: number
  group_name: string
  subject: string
  professor_name?: string
  room_name: string
  weekday: string
  start_time: string
  end_time: string
}
type Proposal = {
  id: number
  author_name: string
  author_reputation: number
  subject: string
  from_room: string
  to_room: string
  reason: string
  status: string
  yes_votes: number
  no_votes: number
  confidence: number
  official_priority: boolean
  moderation_note: string
}
type Audit = {
  id: number
  action: string
  details: string
  created_at: string
}
type ScheduleConflict = {
  left: Schedule
  right: Schedule
  kinds: string[]
}
type MapNode = { id: string; x: number; y: number; z: number; floor: number; label?: string; type?: string }
type MapEdge = { id?: string; from: string; to: string; type?: string; cost?: number; accessible?: boolean }
type MapPoi = { id: string; name: string; x: number; y: number; z?: number; floor: number; sector?: string; nodeId?: string; navigationNode?: string }
type MapData = {
  building?: { id: string; name: string; version: string }
  floors?: { id?: string; name?: string; level: number }[]
  nodes: MapNode[]
  edges: MapEdge[]
  pois: MapPoi[]
  [key: string]: unknown
}
type CurrentMap = {
  id: number
  version: string
  name: string
  status: string
  checksum: string
  map_data: MapData
}
type MapVersion = Omit<CurrentMap, 'map_data'> & {
  notes: string
  created_at: string
  published_at?: string
}
type RouteClosure = {
  id: number
  edge_id: string
  floor: number
  reason: string
  status: string
  created_by_name?: string
  starts_at: string
  ends_at?: string
}
type PositioningAnchor = {
  id: number
  anchor_code: string
  node_id: string
  kind: string
  x: number
  y: number
  z: number
  floor: number
  heading: number
}
type IntegrationStatus = {
  environment: string
  commercial_launch: boolean
  ready: boolean
  checks: Record<string, boolean>
  missing: string[]
  message: string
}

const ADMIN_AUTH_MODE =
  import.meta.env.VITE_GRANMAP_ADMIN_AUTH_MODE === 'bearer' ? 'bearer' : 'cookie'


function App() {
  const [tab, setTab] = useState('dashboard')
  const [token, setToken] = useState(() => {
    const storedToken = sessionStorage.getItem('granmap.admin.token')
    if (storedToken) return storedToken
    return hasAdminSession() ? 'cookie' : ''
  })
  const [user, setUser] = useState<User | null>(null)
  const [courses, setCourses] = useState<Course[]>([])
  const [subjects, setSubjects] = useState<Subject[]>([])
  const [groups, setGroups] = useState<AcademicGroup[]>([])
  const [professors, setProfessors] = useState<Professor[]>([])
  const [rooms, setRooms] = useState<Room[]>([])
  const [schedules, setSchedules] = useState<Schedule[]>([])
  const [proposals, setProposals] = useState<Proposal[]>([])
  const [audits, setAudits] = useState<Audit[]>([])
  const [users, setUsers] = useState<User[]>([])
  const [conflicts, setConflicts] = useState<ScheduleConflict[]>([])
  const [currentMap, setCurrentMap] = useState<CurrentMap | null>(null)
  const [mapVersions, setMapVersions] = useState<MapVersion[]>([])
  const [closures, setClosures] = useState<RouteClosure[]>([])
  const [anchors, setAnchors] = useState<PositioningAnchor[]>([])
  const [integrationStatus, setIntegrationStatus] = useState<IntegrationStatus | null>(null)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')

  const canAdmin = user?.role === 'admin' || user?.role === 'coordination'
  const canModerate =
    canAdmin || user?.role === 'moderator'

  const tabs = useMemo(() => {
    const items = [
      ['dashboard', 'Dashboard'],
      ['community', 'Comunidade'],
    ]
    if (canAdmin) {
      items.splice(
        1,
        0,
        ['courses', 'Cursos'],
        ['subjects', 'Disciplinas'],
        ['groups', 'Turmas'],
        ['professors', 'Professores'],
        ['rooms', 'Salas'],
        ['schedules', 'Ensalamento'],
        ['maps', 'Mapa & versões'],
        ['operation', 'Operação do mapa'],
      )
      if (user?.role === 'admin') items.push(['users', 'Usuários'])
    }
    if (canModerate) items.push(['audit', 'Auditoria'])
    return items
  }, [canAdmin, canModerate, user?.role])

  const tabSubtitle = (id: string) => ({
    operation: 'Interdite corredores ou rampas e gerencie os pontos QR de localização.',
    audit: 'Histórico legível de alterações acadêmicas, publicações do mapa, interdições e moderação.',
    dashboard: 'Visão geral da base acadêmica e prontidão institucional.',
    community: 'Sugestões enviadas por alunos e revisão da equipe de moderação.',
  }[id] ?? 'Dados oficiais têm prioridade sobre contribuições comunitárias.')

  const refresh = async () => {
    try {
      await getJson('/health')
      const [c, su, g, p, r, s, pr, integrations] = await Promise.all([
        getJson<Course[]>('/courses'),
        getJson<Subject[]>('/subjects'),
        getJson<AcademicGroup[]>('/groups'),
        getJson<Professor[]>('/professors'),
        getJson<Room[]>('/rooms'),
        getJson<Schedule[]>('/schedules'),
        getJson<Proposal[]>('/proposals', token || undefined),
        getJson<IntegrationStatus>('/integrations/status'),
      ])
      setCourses(c)
      setSubjects(su)
      setGroups(g)
      setProfessors(p)
      setRooms(r)
      setSchedules(s)
      setProposals(pr)
      setIntegrationStatus(integrations)

      if (token) {
        const current = await getJson<User>('/auth/me', token)
        setUser(current)
        if (
          current.role === 'admin' ||
          current.role === 'coordination' ||
          current.role === 'moderator'
        ) {
          const [auditItems, map] = await Promise.all([
            getJson<Audit[]>('/audit', token),
            getJson<CurrentMap>('/maps/current'),
          ])
          setAudits(auditItems)
          setCurrentMap(map)
        }
        if (current.role === 'admin' || current.role === 'coordination') {
          setConflicts(await getJson<ScheduleConflict[]>('/schedule-conflicts', token))
          const [versions, allClosures, mapAnchors] = await Promise.all([
            getJson<MapVersion[]>('/maps/versions', token),
            getJson<RouteClosure[]>('/navigation/closures/all', token),
            getJson<PositioningAnchor[]>('/positioning/anchors'),
          ])
          setMapVersions(versions)
          setClosures(allClosures)
          setAnchors(mapAnchors)
        }
        if (current.role === 'admin') {
          setUsers(await getJson<User[]>('/users', token))
        }
      } else {
        setUser(null)
      }
    } catch (cause) {
      if (cause instanceof ApiError && cause.status === 401) {
        sessionStorage.removeItem('granmap.admin.session')
        sessionStorage.removeItem('granmap.admin.token')
        setToken('')
        setUser(null)
        setError('A sessão expirou. Entre novamente.')
        return
      }
      setError(cause instanceof Error ? cause.message : 'Servidor indisponível.')
    }
  }

  useEffect(() => {
    void refresh()
  }, [token])

  useEffect(() => {
    if (!tabs.some(([id]) => id === tab)) setTab('dashboard')
  }, [tab, tabs])

  const login = async (email: string, password: string) => {
    setError('')
    const endpoint = ADMIN_AUTH_MODE === 'bearer' ? '/auth/login' : '/auth/web-login'
    const result = await postJson<AuthResult>(endpoint, { email, password })
    if (!['admin', 'coordination', 'moderator'].includes(result.user.role)) {
      throw new ApiError(
        'Esta conta não possui acesso ao painel administrativo.',
        403,
      )
    }
    if (ADMIN_AUTH_MODE === 'bearer') {
      if (!result.token) throw new ApiError('Sessão não recebida pelo backend.', 500)
      sessionStorage.removeItem('granmap.admin.session')
      sessionStorage.setItem('granmap.admin.token', result.token)
      setToken(result.token)
    } else {
      sessionStorage.removeItem('granmap.admin.token')
      sessionStorage.setItem('granmap.admin.session', 'cookie')
      setToken('cookie')
    }
    setUser(result.user)
  }

  const logout = async () => {
    try {
      if (token) {
        await request('/auth/web-logout', { method: 'POST' }, token)
      }
    } finally {
      sessionStorage.removeItem('granmap.admin.session')
      sessionStorage.removeItem('granmap.admin.token')
      setToken('')
      setUser(null)
      setTab('dashboard')
    }
  }

  const mutate = async (action: () => Promise<unknown>, success: string) => {
    setError('')
    setNotice('')
    try {
      await action()
      setNotice(success)
      await refresh()
      return true
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Operação não concluída.')
      return false
    }
  }

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark">➤</span>
          <span>
            Gran<span className="brand-accent">Map</span>
            <small>Painel administrativo</small>
          </span>
        </div>
        {user && (
          <div className="nav">
            {tabs.map(([id, label]) => (
              <button
                key={id}
                className={tab === id ? 'active' : ''}
                onClick={() => setTab(id)}
              >
                {label}
              </button>
            ))}
          </div>
        )}
      </aside>

      <main className="main">
        <div className="header">
          <div>
            <h1>{user ? tabs.find(([id]) => id === tab)?.[1] : 'Acesso institucional'}</h1>
            <div>{user ? tabSubtitle(tab) : 'Dados oficiais têm prioridade sobre contribuições comunitárias.'}</div>
          </div>
          <div className="header-actions">
            {user && (
              <>
                <span>{user.name} · {roleLabel(user.role)}</span>
                <button className="secondary" onClick={() => void logout()}>Sair</button>
              </>
            )}
          </div>
        </div>

        {error && <div className="message error">{error}</div>}
        {notice && <div className="message notice">{notice}</div>}

        {!user ? (
          <LoginPanel onLogin={login} />
        ) : (
          <>
            {tab === 'dashboard' && (
              <>
                <div className="grid">
                  <Metric label="Cursos" value={courses.length} />
                  <Metric label="Professores" value={professors.length} />
                  <Metric label="Salas mapeadas" value={rooms.length} />
                  <Metric label="Aulas" value={schedules.length} />
                </div>
                <div className="card spaced">
                  <h2>Governança ativa</h2>
                  <p>
                    {proposals.length} contribuições registradas; alterações na
                    base acadêmica exigem papel de coordenação ou administração.
                    Moderadores revisam a comunidade sem alterar o cadastro oficial.
                  </p>
                </div>
                {integrationStatus && (
                  <div className="card spaced">
                    <div className="section-heading">
                      <div>
                        <small>AMBIENTE</small>
                        <h2>Status do ambiente</h2>
                      </div>
                      <span className={`badge ${integrationStatus.ready ? 'confirmed' : 'voting'}`}>
                        {integrationStatus.ready ? 'Pronto' : 'Em operação'}
                      </span>
                    </div>
                    <div className="readiness-list">
                      {Object.entries(integrationStatus.checks).map(([key, configured]) => (
                        <span className={`readiness-check ${configured ? 'ready' : 'missing'}`} key={key}>
                          <b>{configured ? '✓' : '○'}</b> {integrationLabel(key)}
                        </span>
                      ))}
                    </div>
                    <small>{integrationStatus.message}</small>
                  </div>
                )}
              </>
            )}

            {tab === 'courses' && canAdmin && (
              <CoursePage
                items={courses}
                onCreate={name => mutate(
                  () => postJson('/courses', { name }, token),
                  'Curso cadastrado.',
                )}
                onUpdate={(id, name) => mutate(
                  () => putJson(`/courses/${id}`, { name }, token),
                  'Curso atualizado.',
                )}
                onDelete={id => mutate(
                  () => deleteJson(`/courses/${id}`, token),
                  'Curso excluído.',
                )}
              />
            )}

            {tab === 'subjects' && canAdmin && (
              <SubjectPage
                items={subjects}
                courses={courses}
                onCreate={(courseId, name) => mutate(
                  () => postJson('/subjects', { course_id: courseId, name }, token),
                  'Disciplina cadastrada.',
                )}
                onUpdate={(id, courseId, name) => mutate(
                  () => putJson(`/subjects/${id}`, { course_id: courseId, name }, token),
                  'Disciplina atualizada.',
                )}
                onDelete={id => mutate(
                  () => deleteJson(`/subjects/${id}`, token),
                  'Disciplina excluída.',
                )}
              />
            )}

            {tab === 'groups' && canAdmin && (
              <GroupPage
                items={groups}
                courses={courses}
                onCreate={(courseId, semester, name) => mutate(
                  () => postJson('/groups', {
                    course_id: courseId,
                    semester,
                    name,
                  }, token),
                  'Turma cadastrada.',
                )}
                onUpdate={(id, courseId, semester, name) => mutate(
                  () => putJson(`/groups/${id}`, {
                    course_id: courseId,
                    semester,
                    name,
                  }, token),
                  'Turma atualizada.',
                )}
                onDelete={id => mutate(
                  () => deleteJson(`/groups/${id}`, token),
                  'Turma excluída.',
                )}
              />
            )}

            {tab === 'professors' && canAdmin && (
              <ProfessorPage
                items={professors}
                onCreate={(name, email) => mutate(
                  () => postJson('/professors', { name, email }, token),
                  'Professor cadastrado.',
                )}
                onUpdate={(id, name, email) => mutate(
                  () => putJson(`/professors/${id}`, { name, email }, token),
                  'Professor atualizado.',
                )}
                onDelete={id => mutate(
                  () => deleteJson(`/professors/${id}`, token),
                  'Professor excluído.',
                )}
              />
            )}

            {tab === 'rooms' && canAdmin && (
              <RoomPage
                items={rooms}
                onCreate={data => mutate(
                  () => postJson('/rooms', data, token),
                  'Ambiente cadastrado.',
                )}
                onUpdate={(id, data) => mutate(
                  () => putJson(`/rooms/${id}`, data, token),
                  'Ambiente atualizado.',
                )}
                onDelete={id => mutate(
                  () => deleteJson(`/rooms/${id}`, token),
                  'Ambiente excluído.',
                )}
              />
            )}

            {tab === 'schedules' && canAdmin && (
              <SchedulePage
                courses={courses}
                professors={professors}
                rooms={rooms}
                schedules={schedules}
                conflicts={conflicts}
                onCreate={data => mutate(
                  () => postJson('/schedules', data, token),
                  'Ensalamento salvo.',
                )}
                onUpdate={(id, data) => mutate(
                  () => putJson(`/schedules/${id}`, data, token),
                  'Ensalamento atualizado.',
                )}
                onDelete={id => mutate(
                  () => deleteJson(`/schedules/${id}`, token),
                  'Ensalamento excluído.',
                )}
              />
            )}

            {tab === 'users' && user.role === 'admin' && (
              <UsersPage
                items={users}
                onRoleChange={(id, role) => mutate(
                  () => putJson(`/users/${id}/role`, { role }, token),
                  'Papel atualizado.',
                )}
              />
            )}

            {tab === 'maps' && canAdmin && currentMap && (
              <MapManagementPage
                current={currentMap}
                versions={mapVersions}
                onCreate={data => mutate(
                  () => postJson('/maps/versions', data, token),
                  'Rascunho de mapa criado e validado.',
                )}
                onPublish={id => mutate(
                  () => postJson(`/maps/versions/${id}/publish`, {}, token),
                  'Versão publicada. Os aplicativos receberão o novo mapa.',
                )}
                onDelete={id => mutate(
                  () => deleteJson(`/maps/versions/${id}`, token),
                  'Rascunho excluído.',
                )}
              />
            )}

            {tab === 'operation' && canAdmin && currentMap && (
              <MapOperationPage
                current={currentMap}
                closures={closures}
                anchors={anchors}
                onCreateClosure={data => mutate(
                  () => postJson('/navigation/closures', data, token),
                  'Interdição ativada; o aplicativo passa a evitar este trecho.',
                )}
                onResolveClosure={id => mutate(
                  () => postJson(`/navigation/closures/${id}/resolve`, {}, token),
                  'Passagem reaberta.',
                )}
                onCreateAnchor={data => mutate(
                  () => postJson('/positioning/anchors', data, token),
                  'Ponto QR cadastrado.',
                )}
                onDisableAnchor={id => mutate(
                  () => deleteJson(`/positioning/anchors/${id}`, token),
                  'Ponto QR removido.',
                )}
              />
            )}

            {tab === 'community' && canModerate && (
              <CommunityPage
                proposals={proposals}
                schedules={schedules}
                onModerate={(id, status, note, officialPriority) => mutate(
                  () => postJson(
                    `/proposals/${id}/moderate`,
                    {
                      status,
                      moderation_note: note,
                      official_priority: officialPriority,
                    },
                    token,
                  ),
                  'Decisão de moderação registrada.',
                )}
                onApply={(proposalId, scheduleId) => mutate(
                  () => postJson(
                    `/proposals/${proposalId}/apply`,
                    { schedule_id: scheduleId },
                    token,
                  ),
                  'Contribuição aplicada à grade oficial e alunos notificados.',
                )}
              />
            )}

            {tab === 'audit' && canModerate && (
              <AuditPage items={audits} users={users} currentMap={currentMap} />
            )}
          </>
        )}
      </main>
    </div>
  )
}

function LoginPanel({
  onLogin,
}: {
  onLogin: (email: string, password: string) => Promise<void>
}) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    setBusy(true)
    setError('')
    try {
      await onLogin(email.trim(), password)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Não foi possível entrar.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="card auth-card">
      <h2>Entrar no GranMap Admin</h2>
      <p>Use uma conta promovida para moderador, coordenação ou administrador.</p>
      <form className="form" onSubmit={submit}>
        <input
          type="email"
          value={email}
          onChange={event => setEmail(event.target.value)}
          placeholder="E-mail"
          required
        />
        <input
          type="password"
          value={password}
          onChange={event => setPassword(event.target.value)}
          placeholder="Senha"
          required
        />
        {error && <div className="message error">{error}</div>}
        <button className="primary" disabled={busy}>
          {busy ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
    </div>
  )
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div className="card">
      <div>{label}</div>
      <div className="metric">{value}</div>
    </div>
  )
}

function CoursePage({
  items,
  onCreate,
  onUpdate,
  onDelete,
}: {
  items: Course[]
  onCreate: (name: string) => Promise<boolean>
  onUpdate: (id: number, name: string) => Promise<boolean>
  onDelete: (id: number) => Promise<boolean>
}) {
  const [name, setName] = useState('')
  return (
    <div className="card">
      <h2>Cursos cadastrados</h2>
      <div className="form">
        <input value={name} onChange={e => setName(e.target.value)} placeholder="Ex.: Engenharia da Computação" />
        <button className="primary" onClick={async () => {
          if (!name.trim()) return
          if (await onCreate(name.trim())) setName('')
        }}>Cadastrar</button>
      </div>
      <div className="entity-list">
        {items.map(item => (
          <div className="entity-row" key={item.id}>
            <span><strong>{item.name}</strong><small>#{item.id}</small></span>
            <div className="actions">
              <button className="secondary" onClick={async () => {
                const next = window.prompt('Nome do curso:', item.name)
                if (next?.trim()) await onUpdate(item.id, next.trim())
              }}>Editar</button>
              <button className="danger" onClick={async () => {
                if (window.confirm(`Excluir ${item.name}?`)) await onDelete(item.id)
              }}>Excluir</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function SubjectPage({
  items,
  courses,
  onCreate,
  onUpdate,
  onDelete,
}: {
  items: Subject[]
  courses: Course[]
  onCreate: (courseId: number, name: string) => Promise<boolean>
  onUpdate: (id: number, courseId: number, name: string) => Promise<boolean>
  onDelete: (id: number) => Promise<boolean>
}) {
  const [courseId, setCourseId] = useState('')
  const [name, setName] = useState('')
  useEffect(() => {
    if (!courseId && courses[0]) setCourseId(String(courses[0].id))
  }, [courseId, courses])
  return (
    <div className="card">
      <h2>Disciplinas</h2>
      <div className="form">
        <select value={courseId} onChange={e => setCourseId(e.target.value)}>
          {courses.map(course => <option key={course.id} value={course.id}>{course.name}</option>)}
        </select>
        <input value={name} onChange={e => setName(e.target.value)} placeholder="Nome da disciplina" />
        <button className="primary" onClick={async () => {
          if (!courseId || !name.trim()) return
          if (await onCreate(Number(courseId), name.trim())) setName('')
        }}>Cadastrar disciplina</button>
      </div>
      <div className="entity-list">
        {items.map(item => (
          <div className="entity-row" key={item.id}>
            <span><strong>{item.name}</strong><small>{item.course_name}</small></span>
            <div className="actions">
              <button className="secondary" onClick={async () => {
                const next = window.prompt('Nome da disciplina:', item.name)
                if (next?.trim()) await onUpdate(item.id, item.course_id, next.trim())
              }}>Editar</button>
              <button className="danger" onClick={async () => {
                if (window.confirm(`Excluir ${item.name}?`)) await onDelete(item.id)
              }}>Excluir</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function GroupPage({
  items,
  courses,
  onCreate,
  onUpdate,
  onDelete,
}: {
  items: AcademicGroup[]
  courses: Course[]
  onCreate: (courseId: number, semester: number, name: string) => Promise<boolean>
  onUpdate: (id: number, courseId: number, semester: number, name: string) => Promise<boolean>
  onDelete: (id: number) => Promise<boolean>
}) {
  const [courseId, setCourseId] = useState('')
  const [semester, setSemester] = useState('4')
  const [name, setName] = useState('EC4A')
  useEffect(() => {
    if (!courseId && courses[0]) setCourseId(String(courses[0].id))
  }, [courseId, courses])
  return (
    <div className="card">
      <h2>Turmas</h2>
      <div className="form">
        <select value={courseId} onChange={e => setCourseId(e.target.value)}>
          {courses.map(course => <option key={course.id} value={course.id}>{course.name}</option>)}
        </select>
        <input type="number" min="1" max="20" value={semester} onChange={e => setSemester(e.target.value)} placeholder="Semestre" />
        <input value={name} onChange={e => setName(e.target.value)} placeholder="Nome da turma" />
        <button className="primary" onClick={() => onCreate(Number(courseId), Number(semester), name.trim())}>Cadastrar turma</button>
      </div>
      <div className="entity-list">
        {items.map(item => (
          <div className="entity-row" key={item.id}>
            <span><strong>{item.name}</strong><small>{item.course_name} • {item.semester}º semestre</small></span>
            <div className="actions">
              <button className="secondary" onClick={async () => {
                const next = window.prompt('Nome da turma:', item.name)
                if (next?.trim()) await onUpdate(item.id, item.course_id, item.semester, next.trim())
              }}>Editar</button>
              <button className="danger" onClick={async () => {
                if (window.confirm(`Excluir ${item.name}?`)) await onDelete(item.id)
              }}>Excluir</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function ProfessorPage({
  items,
  onCreate,
  onUpdate,
  onDelete,
}: {
  items: Professor[]
  onCreate: (name: string, email: string) => Promise<boolean>
  onUpdate: (id: number, name: string, email: string) => Promise<boolean>
  onDelete: (id: number) => Promise<boolean>
}) {
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  return (
    <div className="card">
      <h2>Professores</h2>
      <div className="form">
        <input value={name} onChange={e => setName(e.target.value)} placeholder="Nome" />
        <input value={email} onChange={e => setEmail(e.target.value)} placeholder="E-mail" />
        <button className="primary" onClick={async () => {
          if (!name.trim()) return
          if (await onCreate(name.trim(), email.trim())) {
            setName('')
            setEmail('')
          }
        }}>Cadastrar</button>
      </div>
      <div className="entity-list">
        {items.map(item => (
          <div className="entity-row" key={item.id}>
            <span><strong>{item.name}</strong><small>{item.email || 'Sem e-mail'}</small></span>
            <div className="actions">
              <button className="secondary" onClick={async () => {
                const nextName = window.prompt('Nome:', item.name)
                if (!nextName?.trim()) return
                const nextEmail = window.prompt('E-mail:', item.email) ?? item.email
                await onUpdate(item.id, nextName.trim(), nextEmail.trim())
              }}>Editar</button>
              <button className="danger" onClick={async () => {
                if (window.confirm(`Excluir ${item.name}?`)) await onDelete(item.id)
              }}>Excluir</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function RoomPage({
  items,
  onCreate,
  onUpdate,
  onDelete,
}: {
  items: Room[]
  onCreate: (data: Omit<Room, 'id'>) => Promise<boolean>
  onUpdate: (id: number, data: Omit<Room, 'id'>) => Promise<boolean>
  onDelete: (id: number) => Promise<boolean>
}) {
  const [poiId, setPoiId] = useState('')
  const [name, setName] = useState('')
  const [floor, setFloor] = useState('0')
  return (
    <div className="card">
      <h2>Salas e ambientes</h2>
      <div className="form">
        <input value={poiId} onChange={e => setPoiId(e.target.value)} placeholder="POI ID do mapa" />
        <input value={name} onChange={e => setName(e.target.value)} placeholder="Nome do ambiente" />
        <input value={floor} onChange={e => setFloor(e.target.value)} type="number" placeholder="Piso" />
        <button className="primary" onClick={async () => {
          if (!poiId.trim() || !name.trim()) return
          const saved = await onCreate({
            poi_id: poiId.trim(),
            name: name.trim(),
            floor: Number(floor),
            building: 'Gran',
          })
          if (saved) {
            setPoiId('')
            setName('')
          }
        }}>Cadastrar</button>
      </div>
      <div className="entity-list">
        {items.map(item => (
          <div className="entity-row" key={item.id}>
            <span><strong>{item.name}</strong><small>Piso {item.floor} • {item.poi_id}</small></span>
            <div className="actions">
              <button className="secondary" onClick={async () => {
                const nextName = window.prompt('Nome do ambiente:', item.name)
                if (!nextName?.trim()) return
                await onUpdate(item.id, {
                  poi_id: item.poi_id,
                  name: nextName.trim(),
                  floor: item.floor,
                  building: item.building,
                })
              }}>Editar</button>
              <button className="danger" onClick={async () => {
                if (window.confirm(`Excluir ${item.name}?`)) await onDelete(item.id)
              }}>Excluir</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function SchedulePage({
  courses,
  professors,
  rooms,
  schedules,
  conflicts,
  onCreate,
  onUpdate,
  onDelete,
}: {
  courses: Course[]
  professors: Professor[]
  rooms: Room[]
  schedules: Schedule[]
  conflicts: ScheduleConflict[]
  onCreate: (data: unknown) => Promise<boolean>
  onUpdate: (id: number, data: unknown) => Promise<boolean>
  onDelete: (id: number) => Promise<boolean>
}) {
  const [courseId, setCourseId] = useState('')
  const [professorId, setProfessorId] = useState('')
  const [roomId, setRoomId] = useState('')
  const [subject, setSubject] = useState('')
  const [groupName, setGroupName] = useState('EC4A')
  const [semester, setSemester] = useState('4')
  const [weekday, setWeekday] = useState('Segunda-feira')
  const [startTime, setStartTime] = useState('19:00')
  const [endTime, setEndTime] = useState('20:40')

  useEffect(() => {
    if (!courseId && courses[0]) setCourseId(String(courses[0].id))
    if (!professorId && professors[0]) setProfessorId(String(professors[0].id))
    if (!roomId && rooms[0]) setRoomId(String(rooms[0].id))
  }, [courses, professors, rooms, courseId, professorId, roomId])

  return (
    <div>
      <div className={`conflict-banner ${conflicts.length ? 'has-conflicts' : ''}`}>
        <span className="conflict-icon">{conflicts.length ? '!' : '✓'}</span>
        <span>
          <strong>{conflicts.length ? `${conflicts.length} conflito(s) detectado(s)` : 'Grade sem conflitos'}</strong>
          <small>{conflicts.length ? 'Revise sala, professor ou turma.' : 'Novos horários também são validados antes de salvar.'}</small>
        </span>
      </div>
      <div className="card">
        <h2>Novo ensalamento</h2>
        <div className="form">
          <select value={courseId} onChange={e => setCourseId(e.target.value)}>
            {courses.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}
          </select>
          <input value={semester} onChange={e => setSemester(e.target.value)} type="number" placeholder="Semestre" />
          <input value={groupName} onChange={e => setGroupName(e.target.value)} placeholder="Turma" />
          <input value={subject} onChange={e => setSubject(e.target.value)} placeholder="Disciplina" />
          <select value={professorId} onChange={e => setProfessorId(e.target.value)}>
            {professors.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}
          </select>
          <select value={roomId} onChange={e => setRoomId(e.target.value)}>
            {rooms.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}
          </select>
          <input value={weekday} onChange={e => setWeekday(e.target.value)} placeholder="Dia" />
          <input value={startTime} onChange={e => setStartTime(e.target.value)} type="time" />
          <input value={endTime} onChange={e => setEndTime(e.target.value)} type="time" />
          <button className="primary" onClick={async () => {
            if (!subject.trim() || !courseId || !roomId) return
            const saved = await onCreate({
              course_id: Number(courseId),
              semester: Number(semester),
              group_name: groupName,
              subject,
              professor_id: professorId ? Number(professorId) : null,
              room_id: Number(roomId),
              weekday,
              start_time: startTime,
              end_time: endTime,
            })
            if (saved) setSubject('')
          }}>Salvar ensalamento</button>
        </div>
      </div>

      <div className="card spaced table-wrap">
        <h2>Ensalamento atual</h2>
        <table>
          <thead>
            <tr>
              <th>Curso/Turma</th>
              <th>Disciplina</th>
              <th>Professor</th>
              <th>Sala</th>
              <th>Horário</th>
              <th>Ações</th>
            </tr>
          </thead>
          <tbody>
            {schedules.map(x => (
              <tr key={x.id}>
                <td>{x.course_name} / {x.group_name}</td>
                <td>{x.subject}</td>
                <td>{x.professor_name || '-'}</td>
                <td>{x.room_name}</td>
                <td>{x.weekday} {x.start_time}-{x.end_time}</td>
                <td>
                  <div className="actions">
                    <button className="secondary" onClick={async () => {
                      const nextSubject = window.prompt('Disciplina:', x.subject)
                      if (!nextSubject?.trim()) return
                      await onUpdate(x.id, {
                        course_id: x.course_id,
                        semester: x.semester,
                        group_name: x.group_name,
                        subject: nextSubject.trim(),
                        professor_id: x.professor_id ?? null,
                        room_id: x.room_id,
                        weekday: x.weekday,
                        start_time: x.start_time,
                        end_time: x.end_time,
                      })
                    }}>Editar</button>
                    <button className="danger" onClick={async () => {
                      if (window.confirm(`Excluir ${x.subject}?`)) await onDelete(x.id)
                    }}>Excluir</button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function UsersPage({
  items,
  onRoleChange,
}: {
  items: User[]
  onRoleChange: (id: number, role: string) => Promise<boolean>
}) {
  return (
    <div className="card table-wrap">
      <h2>Usuários e permissões</h2>
      <p>Somente administradores podem alterar papéis institucionais.</p>
      <table>
        <thead>
          <tr>
            <th>Usuário</th>
            <th>Contexto acadêmico</th>
            <th>Reputação</th>
            <th>Papel</th>
          </tr>
        </thead>
        <tbody>
          {items.map(item => (
            <tr key={item.id}>
              <td><strong>{item.name}</strong><br /><small>{item.email}</small></td>
              <td>{item.course_name || '-'}<br /><small>{item.semester || '-'}º • {item.group_name || '-'}</small></td>
              <td>{item.reputation}</td>
              <td>
                <select
                  value={item.role}
                  onChange={event => void onRoleChange(item.id, event.target.value)}
                >
                  <option value="student">Aluno</option>
                  <option value="professor">Professor</option>
                  <option value="moderator">Moderador</option>
                  <option value="coordination">Coordenação</option>
                  <option value="admin">Administrador</option>
                </select>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function CommunityPage({
  proposals,
  onModerate,
  schedules,
  onApply,
}: {
  proposals: Proposal[]
  onModerate: (
    id: number,
    status: string,
    note: string,
    officialPriority: boolean,
  ) => Promise<boolean>
  schedules: Schedule[]
  onApply: (proposalId: number, scheduleId: number) => Promise<boolean>
}) {
  const decide = async (proposal: Proposal, status: string) => {
    const note = window.prompt(
      'Nota da moderação (opcional):',
      proposal.moderation_note,
    )
    if (note === null) return
    await onModerate(proposal.id, status, note, status === 'confirmed')
  }

  const apply = async (proposal: Proposal) => {
    const candidates = schedules.filter(
      item => item.subject.trim().toLocaleLowerCase('pt-BR') ===
        proposal.subject.trim().toLocaleLowerCase('pt-BR'),
    )
    if (candidates.length === 0) {
      window.alert('Nenhuma aula oficial com essa disciplina foi encontrada.')
      return
    }
    const options = candidates
      .map(item => `#${item.id} • ${item.weekday} ${item.start_time} • ${item.room_name}`)
      .join('\n')
    const selected = Number(window.prompt(
      `Informe o ID da aula que receberá a alteração:\n${options}`,
      String(candidates[0].id),
    ))
    if (Number.isInteger(selected) && selected > 0) {
      await onApply(proposal.id, selected)
    }
  }

  return (
    <div className="card table-wrap">
      <h2>Alterações propostas pela comunidade</h2>
      <p>Consenso auxilia a triagem; a decisão institucional fica registrada.</p>
      <table>
        <thead>
          <tr>
            <th>Contribuição</th>
            <th>Autor</th>
            <th>Consenso</th>
            <th>Status</th>
            <th>Moderação</th>
          </tr>
        </thead>
        <tbody>
          {proposals.map(p => (
            <tr key={p.id}>
              <td>
                <strong>{p.subject}</strong><br />
                {p.from_room} → {p.to_room}<br />
                <small>{p.reason}</small>
              </td>
              <td>{p.author_name}<br /><small>{p.author_reputation} reputação</small></td>
              <td>
                {p.yes_votes} sim / {p.no_votes} não<br />
                <small>{Math.round(p.confidence * 100)}% de confiança</small>
              </td>
              <td>
                <span className={`badge ${p.status}`}>{statusLabel(p.status)}</span>
                {p.official_priority && <small className="official">Revisão oficial</small>}
              </td>
              <td>
                <div className="actions">
                  <button className="secondary" onClick={() => decide(p, 'confirmed')}>Confirmar</button>
                  {p.status === 'confirmed' && (
                    <button className="primary" onClick={() => void apply(p)}>Aplicar à grade</button>
                  )}
                  <button className="secondary" onClick={() => decide(p, 'contested')}>Contestar</button>
                  <button className="danger" onClick={() => decide(p, 'rejected')}>Rejeitar</button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {proposals.length === 0 && <p>Nenhuma contribuição aguardando análise.</p>}
    </div>
  )
}

function MapManagementPage({
  current,
  versions,
  onCreate,
  onPublish,
  onDelete,
}: {
  current: CurrentMap
  versions: MapVersion[]
  onCreate: (data: unknown) => Promise<boolean>
  onPublish: (id: number) => Promise<boolean>
  onDelete: (id: number) => Promise<boolean>
}) {
  const [version, setVersion] = useState(`${current.version}-draft`)
  const [name, setName] = useState('Revisão do mapa da faculdade')
  const [notes, setNotes] = useState('')
  const [source, setSource] = useState(() => JSON.stringify(current.map_data, null, 2))
  const [sourceError, setSourceError] = useState('')

  useEffect(() => setSource(JSON.stringify(current.map_data, null, 2)), [current])

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    try {
      const mapData = JSON.parse(source) as MapData
      setSourceError('')
      await onCreate({ version, name, notes, map_data: mapData })
    } catch (cause) {
      setSourceError(cause instanceof Error ? cause.message : 'JSON inválido.')
    }
  }

  let preview = current.map_data
  try { preview = JSON.parse(source) as MapData } catch { /* mantém publicado */ }

  return (
    <div className="map-admin-grid">
      <div className="card">
        <div className="section-heading">
          <div><small>PUBLICADO • {current.version}</small><h2>Editor versionado</h2></div>
          <span className="badge confirmed">checksum {current.checksum.slice(0, 8)}</span>
        </div>
        <MapPreview map={preview} />
        <form className="form" onSubmit={submit}>
          <div className="form-row">
            <input value={version} onChange={event => setVersion(event.target.value)} placeholder="Versão" required />
            <input value={name} onChange={event => setName(event.target.value)} placeholder="Nome da revisão" required />
          </div>
          <input value={notes} onChange={event => setNotes(event.target.value)} placeholder="Notas da revisão e origem do levantamento" />
          <textarea className="map-source" value={source} onChange={event => setSource(event.target.value)} spellCheck={false} aria-label="Dados JSON do mapa" />
          {sourceError && <div className="message error">{sourceError}</div>}
          <div className="actions">
            <button className="primary">Validar e criar rascunho</button>
            <button type="button" className="secondary" onClick={() => {
              try { setSource(JSON.stringify(JSON.parse(source), null, 2)); setSourceError('') }
              catch { setSourceError('O JSON precisa ser corrigido antes de formatar.') }
            }}>Formatar JSON</button>
            <button type="button" className="secondary" onClick={() => setSource(JSON.stringify(current.map_data, null, 2))}>Restaurar publicado</button>
          </div>
        </form>
      </div>
      <div className="card table-wrap">
        <h2>Histórico de versões</h2>
        <table>
          <thead><tr><th>Versão</th><th>Estado</th><th>Ações</th></tr></thead>
          <tbody>{versions.map(item => (
            <tr key={item.id}>
              <td><strong>{item.version}</strong><br /><small>{item.name}</small></td>
              <td><span className={`badge ${item.status === 'published' ? 'confirmed' : ''}`}>{item.status}</span></td>
              <td><div className="actions">
                {item.status === 'draft' && <button className="primary" onClick={() => void onPublish(item.id)}>Publicar</button>}
                {item.status !== 'published' && <button className="danger" onClick={() => void onDelete(item.id)}>Excluir</button>}
              </div></td>
            </tr>
          ))}</tbody>
        </table>
      </div>
    </div>
  )
}

function MapPreview({ map }: { map: MapData }) {
  const floors = [...new Set(map.nodes?.map(node => node.floor) ?? [0])].sort()
  const [floor, setFloor] = useState(floors[0] ?? 0)
  const floorsKey = floors.join(',')
  useEffect(() => {
    if (!floors.includes(floor)) setFloor(floors[0] ?? 0)
  }, [floor, floorsKey])
  const nodes = (map.nodes ?? []).filter(node => node.floor === floor)
  const ids = new Set(nodes.map(node => node.id))
  const nodeById = new Map(nodes.map(node => [node.id, node]))
  const xs = nodes.map(node => node.x)
  const ys = nodes.map(node => node.y)
  const minX = Math.min(...xs, 0) - 8
  const maxX = Math.max(...xs, 100) + 8
  const minY = Math.min(...ys, 0) - 8
  const maxY = Math.max(...ys, 60) + 8
  return (
    <div className="map-preview">
      <div className="floor-switcher">
        {floors.map(item => <button type="button" key={item} className={floor === item ? 'active' : ''} onClick={() => setFloor(item)}>Piso {item}</button>)}
      </div>
      <svg viewBox={`${minX} ${minY} ${maxX - minX} ${maxY - minY}`} role="img" aria-label={`Grafo de navegação do piso ${floor}`}>
        {(map.edges ?? []).filter(edge => ids.has(edge.from) && ids.has(edge.to)).map(edge => {
          const from = nodeById.get(edge.from)!
          const to = nodeById.get(edge.to)!
          return <line key={`${edge.from}__${edge.to}`} x1={from.x} y1={from.y} x2={to.x} y2={to.y} className={edge.accessible === false ? 'edge stairs' : 'edge'} />
        })}
        {nodes.map(node => <g key={node.id}><circle cx={node.x} cy={node.y} r="1.7" /><title>{node.label ?? node.id}</title></g>)}
        {(map.pois ?? []).filter(poi => poi.floor === floor).map(poi => <g key={poi.id}><circle cx={poi.x} cy={poi.y} r="2.7" className="poi" /><title>{poi.name}</title></g>)}
      </svg>
      <small>{nodes.length} nodes • {(map.edges ?? []).length} edges • {(map.pois ?? []).filter(poi => poi.floor === floor).length} POIs neste piso</small>
    </div>
  )
}

function MapOperationPage({
  current,
  closures,
  anchors,
  onCreateClosure,
  onResolveClosure,
  onCreateAnchor,
  onDisableAnchor,
}: {
  current: CurrentMap
  closures: RouteClosure[]
  anchors: PositioningAnchor[]
  onCreateClosure: (data: unknown) => Promise<boolean>
  onResolveClosure: (id: number) => Promise<boolean>
  onCreateAnchor: (data: unknown) => Promise<boolean>
  onDisableAnchor: (id: number) => Promise<boolean>
}) {
  const lookup = useMemo(() => buildMapLookup(current.map_data), [current])
  const nodes = useMemo(
    () => new Map(current.map_data.nodes.map(node => [node.id, node])),
    [current],
  )
  const anchorsByNodeId = useMemo(() => {
    const map = new Map<string, PositioningAnchor[]>()
    for (const anchor of anchors) {
      const list = map.get(anchor.node_id) ?? []
      list.push(anchor)
      map.set(anchor.node_id, list)
    }
    return map
  }, [anchors])

  const activeClosures = useMemo(
    () => closures.filter(item => item.status === 'active'),
    [closures],
  )
  const resolvedClosures = useMemo(
    () => closures.filter(item => item.status !== 'active'),
    [closures],
  )
  const activeEdgeIds = useMemo(
    () => new Set(activeClosures.map(item => item.edge_id)),
    [activeClosures],
  )

  const [closureFloorFilter, setClosureFloorFilter] = useState<number | 'all'>('all')
  const [edgeSearch, setEdgeSearch] = useState('')
  const [edgeId, setEdgeId] = useState(lookup.edgeOptions[0]?.id ?? '')
  const [reason, setReason] = useState('Manutenção temporária')

  const [anchorSearch, setAnchorSearch] = useState('')
  const [nodeId, setNodeId] = useState(lookup.nodeOptions[0]?.id ?? '')
  const [anchorCode, setAnchorCode] = useState('GRAN-')

  const [closureView, setClosureView] = useState<'active' | 'resolved' | 'all'>('active')
  const [mapFloor, setMapFloor] = useState<number>(lookup.floors[0] ?? 0)

  const filteredEdges = useMemo(() => {
    const query = edgeSearch.trim().toLocaleLowerCase('pt-BR')
    return lookup.edgeOptions.filter(option => {
      if (closureFloorFilter !== 'all' && option.floor !== closureFloorFilter) return false
      if (query && !option.searchText.includes(query)) return false
      return true
    })
  }, [lookup.edgeOptions, closureFloorFilter, edgeSearch])

  const filteredNodes = useMemo(() => {
    const query = anchorSearch.trim().toLocaleLowerCase('pt-BR')
    return lookup.nodeOptions.filter(option => !query || option.searchText.includes(query))
  }, [lookup.nodeOptions, anchorSearch])

  useEffect(() => {
    if (filteredEdges.length > 0 && !filteredEdges.some(edge => edge.id === edgeId)) {
      setEdgeId(filteredEdges[0].id)
    }
  }, [filteredEdges, edgeId])

  useEffect(() => {
    if (filteredNodes.length > 0 && !filteredNodes.some(node => node.id === nodeId)) {
      setNodeId(filteredNodes[0].id)
    }
  }, [filteredNodes, nodeId])

  useEffect(() => {
    if (!lookup.floors.includes(mapFloor)) setMapFloor(lookup.floors[0] ?? 0)
  }, [lookup.floors, mapFloor])

  const selectedEdge = lookup.edgeById.get(edgeId)
  const selectedNode = nodes.get(nodeId)
  const poiOptions = filteredNodes.filter(option => option.group === 'poi')
  const corridorOptions = filteredNodes.filter(option => option.group === 'corridor')

  const visibleClosures = closureView === 'active'
    ? activeClosures
    : closureView === 'resolved'
      ? resolvedClosures
      : closures

  const floorNodes = current.map_data.nodes.filter(node => node.floor === mapFloor)
  const floorNodeIds = new Set(floorNodes.map(node => node.id))
  const floorEdges = (current.map_data.edges ?? []).filter(
    edge => floorNodeIds.has(edge.from) && floorNodeIds.has(edge.to),
  )
  const xs = floorNodes.map(node => node.x)
  const ys = floorNodes.map(node => node.y)
  const minX = Math.min(...xs, 0) - 8
  const maxX = Math.max(...xs, 100) + 8
  const minY = Math.min(...ys, 0) - 8
  const maxY = Math.max(...ys, 60) + 8

  return (
    <div className="operation-stack">
      <div className="operation-summary">
        <div className="card">
          <small>INTERDIÇÕES ATIVAS</small>
          <div className="metric">{activeClosures.length}</div>
          <small>{activeClosures.length === 0 ? 'Circulação normal no campus' : 'O app está desviando destes trechos'}</small>
        </div>
        <div className="card">
          <small>PONTOS QR NO CAMPUS</small>
          <div className="metric">{anchors.length}</div>
          <small>Placas ativas para leitura no app</small>
        </div>
        <div className="card">
          <small>MAPA EM PRODUÇÃO</small>
          <div className="metric">{current.version}</div>
          <small>{lookup.floors.map(floor => lookup.floorLabel(floor)).join(' · ')}</small>
        </div>
      </div>

      <div className="card">
        <div className="section-heading">
          <div>
            <small>VISÃO INTERATIVA</small>
            <h2>Mapa do piso para seleção rápida</h2>
          </div>
          <div className="legend-row">
            <span className="legend-item"><i className="dot blocked" /> Interditado</span>
            <span className="legend-item"><i className="dot selected" /> Selecionado</span>
            <span className="legend-item"><i className="dot anchor" /> Ponto QR</span>
          </div>
        </div>
        <div className="map-preview">
          <div className="floor-switcher">
            {lookup.floors.map(floor => (
              <button
                type="button"
                key={floor}
                className={mapFloor === floor ? 'active' : ''}
                onClick={() => setMapFloor(floor)}
              >
                {lookup.floorLabel(floor)}
              </button>
            ))}
          </div>
          <svg
            viewBox={`${minX} ${minY} ${maxX - minX} ${maxY - minY}`}
            role="img"
            aria-label={`Mapa operacional — ${lookup.floorLabel(mapFloor)}`}
          >
            {floorEdges.map(edge => {
              const from = nodes.get(edge.from)
              const to = nodes.get(edge.to)
              if (!from || !to) return null
              const currentId = (edge as MapEdge & { id?: string }).id ?? `${edge.from}__${edge.to}`
              const isBlocked = activeEdgeIds.has(currentId)
              const isSelected = currentId === edgeId
              const classes = [
                'edge',
                'clickable',
                edge.accessible === false ? 'stairs' : '',
                isBlocked ? 'blocked' : '',
                isSelected ? 'selected' : '',
              ].filter(Boolean).join(' ')
              return (
                <line
                  key={currentId}
                  x1={from.x}
                  y1={from.y}
                  x2={to.x}
                  y2={to.y}
                  className={classes}
                  onClick={() => {
                    setClosureFloorFilter('all')
                    setEdgeSearch('')
                    setEdgeId(currentId)
                  }}
                >
                  <title>{lookup.edgeLabelById(currentId)}{isBlocked ? ' (INTERDITADO)' : ''}</title>
                </line>
              )
            })}
            {floorNodes.map(node => {
              const nodeAnchors = anchorsByNodeId.get(node.id) ?? []
              const hasAnchor = nodeAnchors.length > 0
              const isSelected = node.id === nodeId
              return (
                <g
                  key={node.id}
                  className="clickable"
                  onClick={() => {
                    setAnchorSearch('')
                    setNodeId(node.id)
                  }}
                >
                  <circle
                    cx={node.x}
                    cy={node.y}
                    r={hasAnchor ? 2.6 : 1.7}
                    className={[hasAnchor ? 'anchor' : '', isSelected ? 'selected-node' : ''].filter(Boolean).join(' ')}
                  />
                  <title>
                    {lookup.nodeLabel(node.id)}
                    {hasAnchor ? ` • QR: ${nodeAnchors.map(a => a.anchor_code).join(', ')}` : ''}
                  </title>
                </g>
              )
            })}
            {(current.map_data.pois ?? [])
              .filter(poi => poi.floor === mapFloor)
              .map(poi => {
                const linkedNode = (poi.navigationNode || poi.nodeId || '').trim()
                const isSelected = Boolean(linkedNode && linkedNode === nodeId)
                return (
                  <g
                    key={poi.id}
                    className={linkedNode ? 'clickable' : undefined}
                    onClick={() => {
                      if (linkedNode) {
                        setAnchorSearch('')
                        setNodeId(linkedNode)
                      }
                    }}
                  >
                    <circle
                      cx={poi.x}
                      cy={poi.y}
                      r={2.7}
                      className={`poi${isSelected ? ' selected-node' : ''}`}
                    />
                    <title>{poi.name}</title>
                  </g>
                )
              })}
          </svg>
          <small>
            Clique em uma linha do mapa para selecionar o trecho que deseja interditar, ou clique em um círculo para escolher o local do ponto QR.
          </small>
        </div>
      </div>

      <div className="map-admin-grid">
        <div>
          <div className="card">
            <h2>1. Interditar corredor ou rampa</h2>
            <p>
              Feche temporariamente uma passagem em obra, limpeza ou manutenção. O aplicativo passa a recalcular rotas evitando o trecho bloqueado.
            </p>
            <div className="filter-pills">
              <button
                type="button"
                className={closureFloorFilter === 'all' ? 'pill active' : 'pill'}
                onClick={() => setClosureFloorFilter('all')}
              >
                Todos os pisos
              </button>
              {lookup.floors.map(floor => (
                <button
                  type="button"
                  key={floor}
                  className={closureFloorFilter === floor ? 'pill active' : 'pill'}
                  onClick={() => setClosureFloorFilter(floor)}
                >
                  {lookup.floorLabel(floor)}
                </button>
              ))}
            </div>
            <form
              className="form"
              onSubmit={event => {
                event.preventDefault()
                if (!edgeId) return
                void onCreateClosure({
                  edge_id: edgeId,
                  floor: selectedEdge?.floor ?? 0,
                  reason,
                })
              }}
            >
              <label className="form-field">
                <span>Buscar trecho ou sala próxima</span>
                <input
                  value={edgeSearch}
                  onChange={event => setEdgeSearch(event.target.value)}
                  placeholder="Ex.: rampa, Química, Entrada Gran..."
                />
              </label>
              <label className="form-field">
                <span>Trecho / passagem ({filteredEdges.length})</span>
                <select value={edgeId} onChange={event => setEdgeId(event.target.value)} required>
                  {filteredEdges.length === 0 ? (
                    <option value="">Nenhum trecho encontrado para esse filtro</option>
                  ) : (
                    filteredEdges.map(edge => (
                      <option key={edge.id} value={edge.id}>
                        {edge.floorName} • {edge.label}
                      </option>
                    ))
                  )}
                </select>
              </label>
              <label className="form-field">
                <span>Motivo da interdição</span>
                <input
                  value={reason}
                  onChange={event => setReason(event.target.value)}
                  placeholder="Ex.: Manutenção temporária, piso molhado"
                  required
                />
              </label>
              <button className="primary" disabled={!edgeId}>Ativar interdição</button>
            </form>
          </div>

          <div className="card spaced">
            <h2>2. Cadastrar ponto QR de localização</h2>
            <p>
              Associe um código QR físico colado na parede a uma sala, entrada ou ponto do corredor para calibrar a posição de quem escanear pelo celular.
            </p>
            <form
              className="form"
              onSubmit={event => {
                event.preventDefault()
                if (!selectedNode) return
                void onCreateAnchor({
                  anchor_code: anchorCode.trim(),
                  node_id: selectedNode.id,
                  kind: 'qr',
                  x: selectedNode.x,
                  y: selectedNode.y,
                  z: selectedNode.z,
                  floor: selectedNode.floor,
                  heading: 0,
                  metadata: {},
                })
              }}
            >
              <label className="form-field">
                <span>Código impresso no QR</span>
                <input
                  value={anchorCode}
                  onChange={event => setAnchorCode(event.target.value)}
                  placeholder="Ex.: GRAN-ENTRADA-01"
                  required
                />
              </label>
              <label className="form-field">
                <span>Buscar local no mapa</span>
                <input
                  value={anchorSearch}
                  onChange={event => setAnchorSearch(event.target.value)}
                  placeholder="Ex.: Laboratório, Rampa, Entrada..."
                />
              </label>
              <label className="form-field">
                <span>Local no mapa ({filteredNodes.length})</span>
                <select value={nodeId} onChange={event => setNodeId(event.target.value)} required>
                  {poiOptions.length > 0 && (
                    <optgroup label="Salas e locais principais">
                      {poiOptions.map(node => (
                        <option key={node.id} value={node.id}>
                          {node.floorName} • {node.label}
                        </option>
                      ))}
                    </optgroup>
                  )}
                  {corridorOptions.length > 0 && (
                    <optgroup label="Corredores e acessos">
                      {corridorOptions.map(node => (
                        <option key={node.id} value={node.id}>
                          {node.floorName} • {node.label}
                        </option>
                      ))}
                    </optgroup>
                  )}
                  {filteredNodes.length === 0 && (
                    <option value="">Nenhum local encontrado</option>
                  )}
                </select>
              </label>
              <button className="primary" disabled={!selectedNode}>Cadastrar ponto QR</button>
            </form>
          </div>
        </div>

        <div>
          <div className="card table-wrap">
            <div className="section-heading">
              <div>
                <h2>Interdições no campus</h2>
                <small>Controle o que está bloqueado agora e o histórico já reaberto.</small>
              </div>
              <div className="filter-pills">
                <button
                  type="button"
                  className={closureView === 'active' ? 'pill active' : 'pill'}
                  onClick={() => setClosureView('active')}
                >
                  Ativas ({activeClosures.length})
                </button>
                <button
                  type="button"
                  className={closureView === 'resolved' ? 'pill active' : 'pill'}
                  onClick={() => setClosureView('resolved')}
                >
                  Histórico ({resolvedClosures.length})
                </button>
                <button
                  type="button"
                  className={closureView === 'all' ? 'pill active' : 'pill'}
                  onClick={() => setClosureView('all')}
                >
                  Todas ({closures.length})
                </button>
              </div>
            </div>
            <table>
              <thead>
                <tr>
                  <th>Trecho</th>
                  <th>Motivo</th>
                  <th>Situação</th>
                  <th>Ação</th>
                </tr>
              </thead>
              <tbody>
                {visibleClosures.map(item => (
                  <tr key={item.id}>
                    <td>
                      <strong>{lookup.edgeLabelById(item.edge_id)}</strong><br />
                      <small>{lookup.floorLabel(item.floor)}</small>
                    </td>
                    <td>
                      {item.reason}<br />
                      <small>
                        {item.created_by_name ? `${item.created_by_name} · ` : ''}
                        {formatAuditTimestamp(item.starts_at)}
                      </small>
                    </td>
                    <td>
                      <span className={`badge ${item.status === 'active' ? 'contested' : 'confirmed'}`}>
                        {closureStatusLabel(item.status)}
                      </span>
                    </td>
                    <td>
                      {item.status === 'active' && (
                        <button
                          className="secondary"
                          onClick={() => void onResolveClosure(item.id)}
                        >
                          Reabrir
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {visibleClosures.length === 0 && (
              <p>
                {closureView === 'active'
                  ? 'Nenhuma interdição ativa no momento.'
                  : 'Nenhum registro nesta visualização.'}
              </p>
            )}
          </div>

          <div className="card spaced table-wrap">
            <h2>Pontos QR cadastrados ({anchors.length})</h2>
            <p>Placas reconhecidas pelo leitor do aplicativo para reposicionar o usuário.</p>
            <table>
              <thead>
                <tr>
                  <th>Código QR</th>
                  <th>Localização no prédio</th>
                  <th>Ação</th>
                </tr>
              </thead>
              <tbody>
                {anchors.map(anchor => (
                  <tr key={anchor.id}>
                    <td><code>{anchor.anchor_code}</code></td>
                    <td>
                      <strong>{lookup.nodeLabel(anchor.node_id)}</strong><br />
                      <small>{lookup.floorLabel(anchor.floor)}</small>
                    </td>
                    <td>
                      <button
                        className="danger"
                        onClick={() => void onDisableAnchor(anchor.id)}
                      >
                        Remover
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {anchors.length === 0 && <p>Nenhum ponto QR cadastrado ainda.</p>}
          </div>
        </div>
      </div>
    </div>
  )
}

function AuditPage({
  items,
  users,
  currentMap,
}: {
  items: Audit[]
  users: User[]
  currentMap: CurrentMap | null
}) {
  const [categoryFilter, setCategoryFilter] = useState<'all' | AuditCategory>('all')
  const [search, setSearch] = useState('')

  const usersById = useMemo(
    () => new Map(users.map(item => [item.id, item])),
    [users],
  )
  const usersByEmail = useMemo(
    () => new Map(users.map(item => [item.email.toLowerCase(), item])),
    [users],
  )
  const mapLookup = useMemo(
    () => (currentMap ? buildMapLookup(currentMap.map_data) : null),
    [currentMap],
  )

  const entries = useMemo(
    () => items.map(item => ({
      id: item.id,
      ...formatAuditEntry(item, {
        usersById,
        usersByEmail,
        edgeLabelById: mapLookup?.edgeLabelById,
      }),
    })),
    [items, usersById, usersByEmail, mapLookup],
  )

  const counts = useMemo(() => {
    const mapCounts: Record<AuditCategory, number> = {
      map: 0,
      academic: 0,
      community: 0,
      system: 0,
    }
    for (const entry of entries) mapCounts[entry.category] += 1
    return mapCounts
  }, [entries])

  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase('pt-BR')
    return entries.filter(entry => {
      if (categoryFilter !== 'all' && entry.category !== categoryFilter) return false
      if (query && !entry.searchText.includes(query)) return false
      return true
    })
  }, [entries, categoryFilter, search])

  return (
    <div className="card table-wrap">
      <div className="section-heading">
        <div>
          <h2>Histórico de ações</h2>
          <small>Exibindo {filtered.length} de {entries.length} registros mais recentes</small>
        </div>
        <input
          className="search-input"
          value={search}
          onChange={event => setSearch(event.target.value)}
          placeholder="Buscar por ação, usuário, sala ou turma..."
          aria-label="Buscar na auditoria"
        />
      </div>

      <div className="filter-pills">
        <button
          type="button"
          className={categoryFilter === 'all' ? 'pill active' : 'pill'}
          onClick={() => setCategoryFilter('all')}
        >
          Tudo ({entries.length})
        </button>
        <button
          type="button"
          className={categoryFilter === 'map' ? 'pill active' : 'pill'}
          onClick={() => setCategoryFilter('map')}
        >
          Mapa e operação ({counts.map})
        </button>
        <button
          type="button"
          className={categoryFilter === 'academic' ? 'pill active' : 'pill'}
          onClick={() => setCategoryFilter('academic')}
        >
          Acadêmico ({counts.academic})
        </button>
        <button
          type="button"
          className={categoryFilter === 'community' ? 'pill active' : 'pill'}
          onClick={() => setCategoryFilter('community')}
        >
          Comunidade ({counts.community})
        </button>
        <button
          type="button"
          className={categoryFilter === 'system' ? 'pill active' : 'pill'}
          onClick={() => setCategoryFilter('system')}
        >
          Sistema e acessos ({counts.system})
        </button>
      </div>

      <table>
        <thead>
          <tr>
            <th>Quando</th>
            <th>Categoria</th>
            <th>O que aconteceu</th>
            <th>Responsável</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map(entry => (
            <tr key={entry.id}>
              <td className="nowrap">{entry.when}</td>
              <td>
                <span className={`badge ${entry.category === 'map' ? 'voting' : entry.category === 'academic' ? 'confirmed' : ''}`}>
                  {entry.categoryLabel}
                </span>
              </td>
              <td>
                <strong>{entry.title}</strong><br />
                <span>{entry.summary}</span>
                {entry.rawDetails && (
                  <details className="audit-tech">
                    <summary>Registro técnico</summary>
                    <code>{entry.rawAction} · {entry.rawDetails}</code>
                  </details>
                )}
              </td>
              <td>{entry.actor}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {filtered.length === 0 && (
        <p>
          {entries.length === 0
            ? 'Nenhuma movimentação registrada ainda.'
            : 'Nenhum registro encontrado para esse filtro.'}
        </p>
      )}
    </div>
  )
}

function integrationLabel(key: string) {
  return {
    mapa_institucional: 'Mapa aprovado',
    calibracao_indoor: 'Calibração indoor',
    sso: 'SSO institucional',
    erp_academico: 'ERP acadêmico',
    push: 'Push FCM/APNs',
  }[key] ?? key
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>,
)
