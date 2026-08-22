const API = import.meta.env.VITE_GRANMAP_API_URL ?? 'http://127.0.0.1:8000'

export class ApiError extends Error {
  status: number
  kind: 'network' | 'timeout' | 'http'
  requestId?: string
  retryAfter?: number

  constructor(
    message: string,
    status: number,
    options: {
      kind?: 'network' | 'timeout' | 'http'
      requestId?: string
      retryAfter?: number
    } = {},
  ) {
    super(message)
    this.status = status
    this.kind = options.kind ?? 'http'
    this.requestId = options.requestId
    this.retryAfter = options.retryAfter
  }
}

function cookieValue(name: string) {
  const prefix = `${encodeURIComponent(name)}=`
  const item = document.cookie
    .split(';')
    .map(value => value.trim())
    .find(value => value.startsWith(prefix))
  return item ? decodeURIComponent(item.slice(prefix.length)) : ''
}

export function hasAdminSession() {
  return sessionStorage.getItem('granmap.admin.session') === 'cookie' ||
    Boolean(cookieValue('granmap_csrf'))
}

export async function request<T>(
  path: string,
  options: RequestInit = {},
  token?: string,
): Promise<T> {
  const method = (options.method ?? 'GET').toUpperCase()
  const attempts = method === 'GET' ? 3 : 1
  const requestId = globalThis.crypto?.randomUUID?.() ??
    `gm-admin-${Date.now()}-${Math.random().toString(16).slice(2)}`

  for (let attempt = 1; attempt <= attempts; attempt++) {
    const controller = new AbortController()
    const timeout = globalThis.setTimeout(() => controller.abort(), 8_000)
    try {
      const response = await fetch(`${API}${path}`, {
        ...options,
        signal: controller.signal,
        credentials: 'include',
        headers: {
          Accept: 'application/json',
          'X-Request-ID': requestId,
          'X-GranMap-Admin-Version': '0.5.0',
          ...(options.body ? { 'Content-Type': 'application/json' } : {}),
          ...(token && token !== 'cookie' ? { Authorization: `Bearer ${token}` } : {}),
          ...(method !== 'GET' && cookieValue('granmap_csrf')
            ? { 'X-CSRF-Token': cookieValue('granmap_csrf') }
            : {}),
          ...options.headers,
        },
      })
      if (!response.ok) {
        if (attempt < attempts && shouldRetry(response.status)) {
          await delay(retryDelay(response, attempt))
          continue
        }
        let message = `Erro ${response.status}`
        try {
          const body = await response.json()
          message = typeof body.detail === 'string'
            ? body.detail
            : body.detail?.message ?? message
        } catch {
          // Mantém a mensagem HTTP quando a resposta não for JSON.
        }
        throw new ApiError(message, response.status, {
          requestId: response.headers.get('x-request-id') ?? requestId,
          retryAfter: Number(response.headers.get('retry-after')) || undefined,
        })
      }
      if (response.status === 204) return undefined as T
      return await response.json() as T
    } catch (error) {
      if (error instanceof ApiError) throw error
      if (attempt < attempts) {
        await delay(250 * 2 ** (attempt - 1))
        continue
      }
      if (error instanceof DOMException && error.name === 'AbortError') {
        throw new ApiError('O servidor demorou para responder.', 0, {
          kind: 'timeout',
          requestId,
        })
      }
      throw new ApiError('Sem conexão com o GranMap.', 0, {
        kind: 'network',
        requestId,
      })
    } finally {
      globalThis.clearTimeout(timeout)
    }
  }
  throw new ApiError('Não foi possível concluir a requisição.', 0, {
    kind: 'network',
    requestId,
  })
}

function shouldRetry(status: number) {
  return status === 408 || status === 429 || status >= 500
}

function retryDelay(response: Response, attempt: number) {
  const retryAfter = Number(response.headers.get('retry-after'))
  return retryAfter > 0 ? Math.min(retryAfter, 10) * 1_000 : 250 * 2 ** (attempt - 1)
}

function delay(milliseconds: number) {
  return new Promise(resolve => globalThis.setTimeout(resolve, milliseconds))
}

export const getJson = <T,>(path: string, token?: string) =>
  request<T>(path, {}, token)

export const postJson = <T,>(path: string, data: unknown, token?: string) =>
  request<T>(path, { method: 'POST', body: JSON.stringify(data) }, token)

export const putJson = <T,>(path: string, data: unknown, token?: string) =>
  request<T>(path, { method: 'PUT', body: JSON.stringify(data) }, token)

export const deleteJson = <T,>(path: string, token?: string) =>
  request<T>(path, { method: 'DELETE' }, token)
